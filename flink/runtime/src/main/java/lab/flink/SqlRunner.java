package lab.flink;

import org.apache.flink.table.api.EnvironmentSettings;
import org.apache.flink.table.api.StatementSet;
import org.apache.flink.table.api.TableEnvironment;
import org.apache.flink.table.api.TableResult;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;

public final class SqlRunner {
  private SqlRunner() {
  }

  public static void main(String[] args) throws Exception {
    if (args.length != 1) {
      throw new IllegalArgumentException("Usage: SqlRunner <sql-file>");
    }

    String sql = Files.readString(Path.of(args[0]));
    List<String> statements = splitStatements(sql);
    if (statements.isEmpty()) {
      throw new IllegalArgumentException("No SQL statements found in " + args[0]);
    }

    EnvironmentSettings settings = EnvironmentSettings.newInstance().inStreamingMode().build();
    TableEnvironment tableEnv = TableEnvironment.create(settings);
    StatementSet statementSet = tableEnv.createStatementSet();
    int insertCount = 0;

    for (String statement : statements) {
      System.out.println("Executing SQL statement: " + firstLine(statement));
      if (isInsert(statement)) {
        statementSet.addInsertSql(statement);
        insertCount++;
      } else {
        tableEnv.executeSql(statement);
      }
    }

    if (insertCount == 0) {
      return;
    }

    TableResult result = statementSet.execute();
    Optional<org.apache.flink.core.execution.JobClient> jobClient = result.getJobClient();
    if (jobClient.isPresent()) {
      jobClient.get().getJobExecutionResult().get();
    } else {
      result.await();
    }
  }

  private static boolean isInsert(String statement) {
    return statement.trim().toUpperCase(Locale.ROOT).startsWith("INSERT ");
  }

  private static String firstLine(String statement) {
    String compact = statement.trim().replaceAll("\\s+", " ");
    return compact.length() > 120 ? compact.substring(0, 120) + "..." : compact;
  }

  static List<String> splitStatements(String sql) {
    List<String> statements = new ArrayList<>();
    StringBuilder current = new StringBuilder();
    boolean inSingleQuote = false;
    boolean inBacktick = false;
    boolean inLineComment = false;
    boolean inBlockComment = false;

    for (int i = 0; i < sql.length(); i++) {
      char c = sql.charAt(i);
      char next = i + 1 < sql.length() ? sql.charAt(i + 1) : '\0';

      if (inLineComment) {
        if (c == '\n') {
          inLineComment = false;
          current.append(c);
        }
        continue;
      }

      if (inBlockComment) {
        if (c == '*' && next == '/') {
          inBlockComment = false;
          i++;
        }
        continue;
      }

      if (!inSingleQuote && !inBacktick && c == '-' && next == '-') {
        inLineComment = true;
        i++;
        continue;
      }

      if (!inSingleQuote && !inBacktick && c == '/' && next == '*') {
        inBlockComment = true;
        i++;
        continue;
      }

      if (!inBacktick && c == '\'' && !isEscaped(sql, i)) {
        inSingleQuote = !inSingleQuote;
      } else if (!inSingleQuote && c == '`') {
        inBacktick = !inBacktick;
      }

      if (!inSingleQuote && !inBacktick && c == ';') {
        addStatement(statements, current);
        current.setLength(0);
      } else {
        current.append(c);
      }
    }

    addStatement(statements, current);
    return statements;
  }

  private static boolean isEscaped(String sql, int index) {
    int slashCount = 0;
    for (int i = index - 1; i >= 0 && sql.charAt(i) == '\\'; i--) {
      slashCount++;
    }
    return slashCount % 2 == 1;
  }

  private static void addStatement(List<String> statements, StringBuilder current) {
    String statement = current.toString().trim();
    if (!statement.isEmpty()) {
      statements.add(statement);
    }
  }
}
