// flixw 0.32.0 -- stage 0. GENERATED: this is the documented source with its
// comments removed, which is why it reads as bare mechanism.
//
// The commentary is the security story -- why each check exists, and which
// cheaper option was rejected. Read it before trusting this file with a
// download:
//
//   https://wstein.github.io/flixw/          docs, and the lock schema
//   https://github.com/wstein/flixw          the source this was made from
//
// Reproducible on purpose: `java tests/strip.java 0.32.0` at tag vsrc/flixw.java <version> regenerates
// this file byte for byte, so the readable source and the running one can be
// checked against each other rather than taken on trust.
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.math.BigInteger;
import java.net.URI;
import java.net.URL;
import java.net.URLClassLoader;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.time.Duration;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class flixw {

  static final String WRAPPER_VERSION = "0.32.0";
  static final String WRAPPER_DIR = ".flixw";
  static final int MIN_JAVA = 21;

  static final int SOURCE_FLOOR = 16;

  static final int TESTED_CEILING = 26;

  static final Duration PROBE_TIMEOUT = Duration.ofSeconds(20);
  static final Duration HELP_TIMEOUT = Duration.ofSeconds(30);
  static final int HELP_CAP = 1 << 20;

  static final List<String> WRAPPER_VERBS =
    List.of("pin", "info", "doctor", "validate", "help", "plugin", "task", "examples", "local");

  static final List<String> BUILTIN_VERBS = List.of(
    "init", "check", "build", "build-classes", "build-jar", "build-fatjar", "build-pkg", "clean",
    "doc", "format", "run", "test", "repl", "lsp", "lsp-vscode", "release",
    "outdated", "stat", "eff-check", "eff-lock");

  static final class Fail extends RuntimeException {
    private static final long serialVersionUID = 1L;
    final String code; final int exit;
    Fail(String code, int exit, String msg) { super(msg); this.code = code; this.exit = exit; }
  }
  static Fail fail(String code, int exit, String msg) { return new Fail(code, exit, msg); }
  static Fail w001(String m) { return fail("FLIXW001", 80, m); }
  static Fail w002(String m) { return fail("FLIXW002", 81, m); }
  static Fail w003(String m) { return fail("FLIXW003", 82, m); }
  static Fail w004(String m) { return fail("FLIXW004", 83, m); }
  static Fail w005(String m) { return fail("FLIXW005", 84, m); }
  static Fail w006(String m) { return fail("FLIXW006", 85, m); }
  static Fail w007(String m) { return fail("FLIXW007", 86, m); }
  static Fail w008(String m) { return fail("FLIXW008", 87, m); }
  static Fail w009(String m) { return fail("FLIXW009", 88, m); }

  static void w010(String m) { System.err.println("FLIXW010: " + m); }
  static void w011(String m) { System.err.println("FLIXW011: " + m); }

  static String env(String k) {
    String v = System.getenv(k);
    return (v == null || v.isBlank()) ? null : v;
  }
  static boolean trace() { return env("FLIXW_TRACE") != null; }
  static long T0 = System.nanoTime();
  static void tr(String s) {
    if (trace()) System.err.printf("flixw[%6.1fms] %s%n", (System.nanoTime() - T0) / 1e6, s);
  }

  static final Pattern SEMVERISH = Pattern.compile(
    "[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z](?:[0-9A-Za-z.-]*[0-9A-Za-z])?)?"
   + "(?:\\+[0-9A-Za-z](?:[0-9A-Za-z.-]*[0-9A-Za-z])?)?");

  static String validateVersion(String v, String where) {
    if (v == null) throw w002(where + ": no version");
    for (char c : v.toCharArray())
      if (Character.isWhitespace(c) || c == '/' || c == '\\')
        throw w002(where + ": illegal character in version " + q(v));
    if (v.contains("..")) throw w002(where + ": '..' in version " + q(v));

    if (v.startsWith("v") && SEMVERISH.matcher(v.substring(1)).matches())
      throw w002(where + ": strip the leading 'v' from " + q(v));
    if (!SEMVERISH.matcher(v).matches())
      throw w002(where + ": " + q(v) + " is not an exact version"
          + "\n       ranges, wildcards and empty suffixes are not accepted");
    return v;
  }

  static String stripTagPrefix(String v) {
    return v.length() > 1 && v.charAt(0) == 'v' && Character.isDigit(v.charAt(1))
      ? v.substring(1) : v;
  }

  static String canonical(String v) { int i = v.indexOf('+'); return i < 0 ? v : v.substring(0, i); }

  static String triple(String v) {
    Matcher m = Pattern.compile("^([0-9]+\\.[0-9]+\\.[0-9]+)").matcher(v);
    return m.find() ? m.group(1) : v;
  }

  static String q(String s) { return "'" + s + "'"; }

  static String why(Exception e) {
    String m = e.getMessage();
    return e.getClass().getSimpleName() + (m == null ? "" : ": " + m);
  }

  static String redact(String v) {
    String s = v.replaceAll("(?i)((?:[a-z][a-z0-9+.-]*://)?)[^/@\\s,]*@", "$1***@");
    int i = s.indexOf('?');
    return i < 0 ? s : s.substring(0, i) + "?***";
  }

  static String redactOpts(String v) {
    return redact(v).replaceAll(
      "(?i)(-D[^=\\s]*(?:pass|secret|token|credential)[^=\\s]*=)\\S+", "$1***");
  }

  static final String LOCK_SCHEMA_VERSION = "v1";

  static final String PAGES_BASE = "https://wstein.github.io/flixw/";

  static final String LOCK_SCHEMA_URL =
    PAGES_BASE + "schema/lock-" + LOCK_SCHEMA_VERSION + ".schema.json";

  static final String REPO_PATTERN = "[A-Za-z0-9._-]{1,64}/[A-Za-z0-9._-]{1,100}";

  static final String JAVA_PIN_PATTERN = "[0-9]+(\\.[0-9]+)*";

  record LockField(String table, String key, boolean required, String pattern, String what) {

    String name() { return table.isEmpty() ? key : "[" + table + "] " + key; }
  }

  static final List<LockField> LOCK_SCHEMA = List.of(
    new LockField("", "wrapperVersion", false, SEMVERISH.pattern(),
      "the flixw release that last wrote this lock"),
    new LockField("compiler", "repo", false, REPO_PATTERN,
      "the owner/repository the compiler was fetched from"),
    new LockField("compiler", "version", true, SEMVERISH.pattern(),
      "the exact compiler version: x.y.z, optionally with a prerelease and build metadata"),
    new LockField("compiler", "url", true, "https://[^\\s]+",
      "the https URL the compiler JAR is downloaded from"),
    new LockField("compiler", "sha256", true, "[0-9a-f]{64}",
      "the SHA-256 of that JAR: 64 lowercase hex digits"),
    new LockField("compiler", "reported_version", false, SEMVERISH.pattern(),
      "the version that JAR reports of itself, captured when it was pinned"),
    new LockField("java", "version", false, JAVA_PIN_PATTERN,
      "the Java that runs the compiler: a feature release (21) or an exact one (21.0.12)"));

  static List<String> lockTables() {
    List<String> out = new ArrayList<>();
    for (LockField f : LOCK_SCHEMA) if (!out.contains(f.table())) out.add(f.table());
    return out;
  }

  static String lockSchemaJson() {
    StringBuilder b = new StringBuilder();
    b.append("{\n");
    b.append("  \"$schema\": \"https://json-schema.org/draft/2020-12/schema\",\n");
    b.append("  \"$id\": ").append(jsonString(LOCK_SCHEMA_URL)).append(",\n");
    b.append("  \"title\": \"flixw lock.toml\",\n");
    b.append("  \"description\": ").append(jsonString(
      "The pin written by `./flixw pin`: the repository, exact version, distribution"
     + " URL and SHA-256 of the Flix compiler a project runs. Generated and verified by"
     + " flixw; committed, and not edited by hand.")).append(",\n");
    b.append("  \"type\": \"object\",\n");
    b.append("  \"additionalProperties\": false,\n");

    List<String> tables = lockTables();
    List<String> rootRequired = new ArrayList<>();
    for (String t : tables)
      if (!t.isEmpty() && lockFields(t).stream().anyMatch(LockField::required))
        rootRequired.add(t);
    b.append("  \"required\": ").append(jsonArray(rootRequired)).append(",\n");

    b.append("  \"properties\": {\n");
    List<String> props = new ArrayList<>();
    for (String t : tables) {
      if (t.isEmpty()) { for (LockField f : lockFields(t)) props.add(fieldJson(f, "    ")); }
      else props.add(tableJson(t, "    "));
    }

    props.add(pluginsTableJson("    "));
    b.append(String.join(",\n", props)).append("\n");
    b.append("  }\n");
    b.append("}\n");
    return b.toString();
  }

  static List<LockField> lockFields(String table) {
    List<LockField> out = new ArrayList<>();
    for (LockField f : LOCK_SCHEMA) if (f.table().equals(table)) out.add(f);
    return out;
  }

  static String fieldJson(LockField f, String indent) {
    return indent + jsonString(f.key()) + ": {\n"
      + indent + "  \"type\": \"string\",\n"
      + indent + "  \"description\": " + jsonString(f.what()) + ",\n"
      + indent + "  \"pattern\": " + jsonString("^" + f.pattern() + "$") + "\n"
      + indent + "}";
  }

  static String tableJson(String table, String indent) {
    List<LockField> fields = lockFields(table);
    List<String> required = new ArrayList<>();
    for (LockField f : fields) if (f.required()) required.add(f.key());
    List<String> props = new ArrayList<>();
    for (LockField f : fields) props.add(fieldJson(f, indent + "    "));

    return indent + jsonString(table) + ": {\n"
      + indent + "  \"type\": \"object\",\n"
      + indent + "  \"additionalProperties\": false,\n"
      + (required.isEmpty() ? ""
        : indent + "  \"required\": " + jsonArray(required) + ",\n")
      + indent + "  \"properties\": {\n"
      + String.join(",\n", props) + "\n"
      + indent + "  }\n"
      + indent + "}";
  }

  static String pluginsTableJson(String indent) {
    String i2 = indent + "    ", i3 = i2 + "  ", i4 = i3 + "  ", i5 = i4 + "  ";
    return indent + "\"plugins\": {\n"
      + indent + "  \"type\": \"object\",\n"
      + indent + "  \"description\": " + jsonString(
        "Plugins this project declares -- installed by `flixw plugin install`,"
       + " which writes this table; never a fetch instruction on its own.") + ",\n"

      + indent + "  \"patternProperties\": {\n"
      + i2 + jsonString("^" + PLUGIN_NAME_PATTERN + "$") + ": {\n"
      + i3 + "\"type\": \"object\",\n"
      + i3 + "\"additionalProperties\": false,\n"
      + i3 + "\"required\": [\"version\", \"sha256\"],\n"
      + i3 + "\"properties\": {\n"
      + i4 + "\"version\": {\n"
      + i5 + "\"type\": \"string\",\n"
      + i5 + "\"description\": \"the plugin version last installed\",\n"
      + i5 + "\"pattern\": " + jsonString("^" + SEMVERISH.pattern() + "$") + "\n"
      + i4 + "},\n"
      + i4 + "\"sha256\": {\n"
      + i5 + "\"type\": \"string\",\n"
      + i5 + "\"description\": \"the SHA-256 of the installed artifact:"
           + " 64 lowercase hex digits\",\n"
      + i5 + "\"pattern\": \"^[0-9a-f]{64}$\"\n"
      + i4 + "},\n"
      + i4 + "\"source\": {\n"
      + i5 + "\"type\": \"string\",\n"
      + i5 + "\"description\": \"where this plugin came from;"
           + " informational, never fetched from automatically\"\n"
      + i4 + "},\n"
      + i4 + "\"description\": {\n"
      + i5 + "\"type\": \"string\",\n"
      + i5 + "\"description\": \"what the plugin is for, as it declared itself"
           + " in its jar manifest at install time; shown by `flixw help`\"\n"
      + i4 + "},\n"
      + i4 + "\"command\": {\n"
      + i5 + "\"type\": \"string\",\n"
      + i5 + "\"description\": \"the bare verb this plugin answers, as it declared"
           + " in its jar manifest; the compiler and the wrapper both win over"
           + " it, and it is recorded here so the claim is reviewable\",\n"
      + i5 + "\"pattern\": " + jsonString("^" + PLUGIN_NAME_PATTERN + "$") + "\n"
      + i4 + "}\n"
      + i3 + "}\n"
      + i2 + "}\n"
      + indent + "  },\n"
      + indent + "  \"additionalProperties\": false\n"
      + indent + "}";
  }

  static String jsonArray(List<String> items) {
    List<String> quoted = new ArrayList<>();
    for (String s : items) quoted.add(jsonString(s));
    return quoted.isEmpty() ? "[]" : "[" + String.join(", ", quoted) + "]";
  }

  static String jsonString(String s) {
    StringBuilder b = new StringBuilder("\"");
    for (int i = 0; i < s.length(); i++) {
      char c = s.charAt(i);
      switch (c) {
        case '"'  -> b.append("\\\"");
        case '\\' -> b.append("\\\\");
        case '\n' -> b.append("\\n");
        case '\r' -> b.append("\\r");
        case '\t' -> b.append("\\t");
        default   -> {
          if (c < 0x20) b.append(String.format("\\u%04x", (int) c));
          else b.append(c);
        }
      }
    }
    return b.append('"').toString();
  }

  record Lock(String version, String url, String sha256, String repo, String java,
        String reportedVersion, Map<String, PluginDep> plugins) {}

  record PluginDep(String version, String sha256, String source, String description,
          String command) {}

  record TomlEntry(int line, String table, String key, String value, boolean multiline) {}

  record TomlScan(List<TomlEntry> entries, List<String> tables) {}

  static TomlScan tomlScan(String text, String where) {
    List<TomlEntry> entries = new ArrayList<>();
    List<String> tables = new ArrayList<>();
    String current = "";
    String mlDelim = null;
    int arrayDepth = 0;
    String[] lines = text.split("\n", -1);
    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];

      if (arrayDepth > 0) {
        arrayDepth += bracketDelta(line);
        continue;
      }
      if (mlDelim != null) {
        int e = line.indexOf(mlDelim);
        if (e < 0) continue;
        line = line.substring(e + 3);
        mlDelim = null;
      }
      String t = stripComment(line).trim();
      if (t.isEmpty()) continue;
      if (t.startsWith("[[")) {

        if (!t.endsWith("]]"))
          throw w002(where + ": malformed array-of-tables header " + q(t));
        current = "\u0000array";
        continue;
      }
      if (t.startsWith("[")) {
        int close = t.indexOf(']');
        if (close < 0) throw w002(where + ": unterminated table header " + q(t));

        if (!t.substring(close + 1).isBlank())
          throw w002(where + ": trailing text after table header " + q(t));
        current = String.join(".", splitKey(t.substring(1, close), where));
        tables.add(current);
        continue;
      }
      int eq = t.indexOf('=');
      if (eq < 0) continue;

      List<String> path = splitKey(t.substring(0, eq), where);
      String k = path.get(path.size() - 1);
      String tbl = current;
      if (path.size() > 1) {
        String prefix = String.join(".", path.subList(0, path.size() - 1));
        tbl = current.isEmpty() ? prefix : current + "." + prefix;
      }
      String v = t.substring(eq + 1).trim();
      String delim = v.startsWith("\"\"\"") ? "\"\"\"" : v.startsWith("'''") ? "'''" : null;
      if (delim != null && !v.substring(3).contains(delim)) mlDelim = delim;
      else if (delim == null) arrayDepth = Math.max(0, bracketDelta(v));
      entries.add(new TomlEntry(i, tbl, k, v, delim != null));
    }
    return new TomlScan(entries, tables);
  }

  static boolean isKey(TomlEntry e, String table, String key) {
    return e.table().equals(table) && e.key().equals(key);
  }

  static List<String> splitKey(String raw, String where) {
    List<String> parts = new ArrayList<>();
    StringBuilder cur = new StringBuilder();
    char quote = 0;
    for (int i = 0; i < raw.length(); i++) {
      char c = raw.charAt(i);
      if (quote != 0) { cur.append(c); if (c == quote) quote = 0; }
      else if (c == '"' || c == '\'') { quote = c; cur.append(c); }
      else if (c == '.') { parts.add(cur.toString()); cur.setLength(0); }
      else cur.append(c);
    }
    if (quote != 0) throw w002(where + ": unterminated quoted key " + q(raw.trim()));
    parts.add(cur.toString());
    List<String> out = new ArrayList<>();
    for (String part : parts) {
      String seg = unquote(part.trim());
      if (seg.isEmpty()) throw w002(where + ": empty key segment in " + q(raw.trim()));
      out.add(seg);
    }
    return out;
  }

  static String tomlLookup(String text, String table, String key, String where) {
    TomlScan scan = tomlScan(text, where);
    String value = null;
    int hits = 0;
    for (TomlEntry e : scan.entries()) {
      if (!isKey(e, table, key)) continue;
      if (e.multiline()) throw w002(where + ": " + q(key) + " must be a single-line string");
      hits++;
      String v = e.value();
      if (v.length() < 2 || v.charAt(0) != v.charAt(v.length() - 1)
        || (v.charAt(0) != '"' && v.charAt(0) != '\''))
        throw w002(where + ": " + q(key) + " must be a quoted string, got " + q(v));
      value = v.substring(1, v.length() - 1);
    }
    int tables = 0;
    for (String t : scan.tables()) if (t.equals(table)) tables++;
    if (tables > 1) throw w002(where + ": duplicate [" + table + "] table");
    if (hits > 1) throw w002(where + ": duplicate " + q(key) + " key in [" + table + "]");
    return value;
  }

  static int bracketDelta(String line) {
    String t = stripComment(line);
    int depth = 0;
    boolean sq = false, dq = false;
    for (int i = 0; i < t.length(); i++) {
      char c = t.charAt(i);
      if (c == '\'' && !dq) sq = !sq;
      else if (c == '"' && !sq) dq = !dq;
      else if (!sq && !dq) {
        if (c == '[') depth++;
        else if (c == ']') depth--;
      }
    }
    return depth;
  }

  static String stripComment(String line) {
    boolean s = false, d = false;
    for (int i = 0; i < line.length(); i++) {
      char c = line.charAt(i);
      if (c == '\'' && !d) s = !s;
      else if (c == '"' && !s) d = !d;
      else if (c == '#' && !s && !d) return line.substring(0, i);
    }
    return line;
  }

  static String unquote(String s) {
    if (s.length() >= 2 && (s.charAt(0) == '"' || s.charAt(0) == '\'')
      && s.charAt(s.length() - 1) == s.charAt(0)) return s.substring(1, s.length() - 1);
    return s;
  }

  static String unquoteToml(String v, String where) {
    if (v.length() < 2 || v.charAt(0) != v.charAt(v.length() - 1)
      || (v.charAt(0) != '"' && v.charAt(0) != '\''))
      throw w002(where + ": " + q(v) + " must be a quoted string");
    String inner = v.substring(1, v.length() - 1);
    if (v.charAt(0) == '\'') return inner;
    StringBuilder b = new StringBuilder();
    for (int i = 0; i < inner.length(); i++) {
      char c = inner.charAt(i);
      if (c != '\\') { b.append(c); continue; }
      if (i + 1 >= inner.length()) throw w002(where + ": trailing backslash in " + q(v));
      char n = inner.charAt(++i);
      switch (n) {
        case '"'  -> b.append('"');
        case '\\' -> b.append('\\');
        case 'b'  -> b.append('\b');
        case 't'  -> b.append('\t');
        case 'n'  -> b.append('\n');
        case 'f'  -> b.append('\f');
        case 'r'  -> b.append('\r');

        case 'u', 'U' -> {
          int len = n == 'u' ? 4 : 8;
          if (i + len >= inner.length())
            throw w002(where + ": incomplete \\" + n + " escape in " + q(v));
          String hex = inner.substring(i + 1, i + 1 + len);
          try {
            int cp = Integer.parseInt(hex, 16);
            if (!Character.isValidCodePoint(cp) || (cp >= 0xD800 && cp <= 0xDFFF))
              throw new NumberFormatException();
            b.appendCodePoint(cp);
          } catch (NumberFormatException e) {
            throw w002(where + ": \\" + n + hex
                + " is not a valid Unicode code point in " + q(v));
          }
          i += len;
        }
        default -> throw w002(where + ": invalid escape " + q("\\" + n) + " in " + q(v));
      }
    }
    return b.toString();
  }

  static Path lockPath(Path root) { return root.resolve(WRAPPER_DIR).resolve("lock.toml"); }

  static Path tasksPath(Path root) { return root.resolve(WRAPPER_DIR).resolve("tasks.toml"); }

  static Map<String, String> readTasks(Path root) {
    Path f = tasksPath(root);
    if (!Files.isRegularFile(f)) return Map.of();
    String text;
    try { text = Files.readString(f, StandardCharsets.UTF_8); }
    catch (IOException e) { throw w002("cannot read " + f + ": " + why(e)); }
    String w = f.toString();
    Map<String, String> out = new LinkedHashMap<>();
    for (TomlEntry e : tomlScan(text, w).entries()) {
      if (!e.table().isEmpty())
        throw w002(w + ": [" + e.table() + "] -- tasks.toml holds only"
            + " name = \"command\" pairs, no tables");
      if (e.multiline())
        throw w002(w + ": " + q(e.key()) + " must be a single-line string");
      out.put(e.key(), unquoteToml(e.value(), w));
    }
    return out;
  }

  static Lock readLock(Path lockFile) {
    String text;
    try { text = Files.readString(lockFile, StandardCharsets.UTF_8); }
    catch (IOException e) {
      throw w002("cannot read " + lockFile + ": " + why(e)
          + "\n       run: ./flixw pin <version>");
    }
    String w = lockFile.toString();
    Map<String, String> got = readLockFields(text, w);
    noteUnknownLockKeys(text, w, got.get("wrapperVersion"));
    String u = got.get("compiler.url");
    String j = got.get("java.version");

    validateUrl(u, w);
    if (j != null) validateJavaPin(j, w);

    return new Lock(got.get("compiler.version"), u, got.get("compiler.sha256"),
            got.get("compiler.repo"), j, got.get("compiler.reported_version"),
            readPlugins(text, w));
  }

  static Map<String, PluginDep> readPlugins(String text, String where) {
    Map<String, String> version = new LinkedHashMap<>(), sha = new LinkedHashMap<>(),
              source = new LinkedHashMap<>(), description = new LinkedHashMap<>(),
              command = new LinkedHashMap<>();
    Set<String> seenKeys = new LinkedHashSet<>();
    Set<String> knownKeys = Set.of("version", "sha256", "source", "description",
                   "command");
    for (TomlEntry e : tomlScan(text, where).entries()) {
      if (!e.table().startsWith("plugins.")) continue;
      String name = e.table().substring("plugins.".length());

      if (!validPluginName(name))
        throw w002(where + ": [plugins." + name + "] is not a valid plugin name"
            + " -- lowercase letters, digits and hyphens, starting with a letter");

      if (!knownKeys.contains(e.key())) continue;
      if (!seenKeys.add(name + "." + e.key()))
        throw w002(where + ": duplicate " + q(e.key()) + " key in [plugins." + name + "]");
      if (e.multiline())
        throw w002(where + ": [plugins." + name + "] " + q(e.key())
            + " must be a single-line string");
      String v = unquoteToml(e.value(), where);
      switch (e.key()) {
        case "version" -> version.put(name, v);
        case "sha256" -> sha.put(name, v);
        case "source" -> source.put(name, v);
        case "description" -> description.put(name, v);
        case "command" -> command.put(name, v);
      }
    }
    Map<String, PluginDep> out = new LinkedHashMap<>();
    Set<String> names = new LinkedHashSet<>();
    names.addAll(version.keySet());
    names.addAll(sha.keySet());
    for (String name : names) {
      String v = version.get(name);
      if (v == null)
        throw w002(where + ": [plugins." + name + "] is missing version");
      if (!SEMVERISH.matcher(v).matches())
        throw w002(where + ": [plugins." + name + "] version is " + q(v)
            + "\n       expected x.y.z, optionally with a prerelease and"
            + " build metadata");
      String d = sha.get(name);
      if (d == null)
        throw w002(where + ": [plugins." + name + "] is missing sha256");
      if (!d.matches("[0-9a-f]{64}"))
        throw w002(where + ": [plugins." + name + "] sha256 is " + q(d)
            + "\n       expected 64 lowercase hex digits");
      out.put(name, new PluginDep(v, d, source.get(name),
                    description.getOrDefault(name, ""),
                    command.getOrDefault(name, "")));
    }
    return out;
  }

  static Map<String, String> readLockFields(String text, String where) {
    Map<String, String> got = new LinkedHashMap<>();
    for (LockField f : LOCK_SCHEMA) {
      String v = tomlLookup(text, f.table(), f.key(), where);
      if (v == null) {
        if (!f.required()) continue;
        throw w002(where + ": missing " + f.name() + " -- " + f.what()
            + "\n       run: ./flixw pin <version>");
      }
      if (!v.matches(f.pattern()))
        throw w002(where + ": " + f.name() + " is " + q(v)
            + "\n       expected " + f.what()
            + "\n       run: ./flixw pin <version>");
      got.put(f.table().isEmpty() ? f.key() : f.table() + "." + f.key(), v);
    }
    return got;
  }

  static void noteUnknownLockKeys(String text, String where, String wroteIt) {

    if (!NOTED_LOCKS.add(where)) return;
    if (wroteIt != null && !olderOrSame(wroteIt, WRAPPER_VERSION)) return;
    List<String> unknown = unknownLockKeys(text, where);
    if (unknown.isEmpty()) return;
    w011(where + ": " + String.join(", ", unknown)
     + (unknown.size() == 1 ? " is not a key flixw reads, and is ignored"
                 : " are not keys flixw reads, and are ignored")
     + "\n         the keys a lock may hold: " + LOCK_SCHEMA_URL);
  }

  static final Set<String> NOTED_LOCKS = new LinkedHashSet<>();

  static List<String> unknownLockKeys(String text, String where) {
    List<String> unknown = new ArrayList<>();
    for (TomlEntry e : tomlScan(text, where).entries()) {

      boolean known = e.table().startsWith("plugins.")
             && List.of("version", "sha256", "source", "description", "command")
                .contains(e.key());
      if (!known)
        for (LockField f : LOCK_SCHEMA)
          if (isKey(e, f.table(), f.key())) { known = true; break; }
      String name = e.table().isEmpty() ? e.key() : "[" + e.table() + "] " + e.key();
      if (!known && !unknown.contains(name)) unknown.add(name);
    }
    return unknown;
  }

  static String manifestVersion(Path manifest) {
    if (!Files.isRegularFile(manifest)) return null;
    String text;
    try { text = Files.readString(manifest, StandardCharsets.UTF_8); }
    catch (IOException e) { throw w002("cannot read " + manifest + ": " + why(e)); }
    String declared = tomlLookup(text, "package", "flix", manifest.toString());
    return declared == null ? null : validateVersion(declared, manifest.toString());
  }

  static boolean isWindows() {
    return System.getProperty("os.name", "").toLowerCase(Locale.ROOT).startsWith("windows");
  }
  static boolean isMac() {
    return System.getProperty("os.name", "").toLowerCase(Locale.ROOT).contains("mac");
  }

  static Path cacheHome() {
    String o = env("FLIX_CACHE_HOME");
    if (o != null) return Paths.get(o).toAbsolutePath();
    String home = System.getProperty("user.home");
    if (isWindows()) {
      String local = env("LOCALAPPDATA");
      return Paths.get(local != null ? local : home).resolve("flixw");
    }
    if (isMac()) return Paths.get(home, "Library", "Caches", "flixw");
    String xdg = env("XDG_CACHE_HOME");
    return (xdg != null ? Paths.get(xdg) : Paths.get(home, ".cache")).resolve("flixw");
  }

  static String sha256(Path file) {
    try (InputStream in = Files.newInputStream(file)) {
      MessageDigest md = MessageDigest.getInstance("SHA-256");
      byte[] buf = new byte[1 << 16];
      for (int n; (n = in.read(buf)) > 0; ) md.update(buf, 0, n);
      return String.format("%064x", new BigInteger(1, md.digest()));
    } catch (Exception e) {
      throw w007("cannot hash " + file + ": " + e.getMessage());
    }
  }
  static String sha256(byte[] b) {
    try {
      return String.format("%064x",
        new BigInteger(1, MessageDigest.getInstance("SHA-256").digest(b)));
    } catch (Exception e) { throw w007("cannot hash: " + e.getMessage()); }
  }

  static final String UPSTREAM_REPO = "flix/flix";

  static boolean isUpstream(Lock lock, boolean override) {
    return lock != null && !override
      && (lock.repo() == null || lock.repo().equals(UPSTREAM_REPO));
  }

  static final String PIN_USAGE =
     "usage: ./flixw pin [<owner>/<repo>] [<version>] [--java <version>]"
    + " [--editor-jar=copy|off]"
    + "\n          or: ./flixw pin <owner>/<repo>@<version>   (one token, a fork)"
    + "\n          or: ./flixw pin --refresh   (rewrite the lock in this release's shape)";

  static final String INFO_USAGE = "usage: ./flixw info [--verbose | -v]";
  static final String DOCTOR_USAGE = "usage: ./flixw doctor [--fix]";
  static final String VALIDATE_USAGE = "usage: ./flixw validate";

  static boolean localHelpTopic(List<String> rest) {
    if (rest.isEmpty() || !rest.get(0).equals("local")) return false;
    String selector = rest.size() == 1 ? "--help"
            : rest.size() == 2 && localHelpSubcommand(rest.get(1))
            ? "--help=" + rest.get(1) : null;
    if (selector == null) return false;
    assetHelp(LOCAL_ASSET, selector); return true;
  }

  static boolean localHelpArgs(List<String> rest) {
    if (rest.isEmpty()) return false;
    if (rest.get(0).equals("--help") || rest.get(0).equals("-h")) {
      assetHelp(LOCAL_ASSET, "--help"); return true;
    }
    if (rest.size() > 1 && (rest.get(1).equals("--help") || rest.get(1).equals("-h"))
      && localHelpSubcommand(rest.get(0))) {
      assetHelp(LOCAL_ASSET, "--help=" + rest.get(0)); return true;
    }
    return false;
  }

  static boolean localHelpSubcommand(String sub) {
    return Set.of("add", "list", "remove", "status", "run", "check", "build", "build-jar",
           "build-fatjar", "build-pkg", "test", "doc").contains(sub);
  }

  static boolean wantsHelp(List<String> rest) {
    int dd = rest.indexOf("--");
    List<String> scanned = dd < 0 ? rest : rest.subList(0, dd);
    return scanned.contains("--help") || scanned.contains("-h");
  }

  static final String PLUGIN_NAME_PATTERN = "[a-z][a-z0-9-]*";

  static boolean validPluginName(String name) { return name.matches(PLUGIN_NAME_PATTERN); }

  record Asset(String name, String url) {}

  static String checkRepo(String repo, String where) {
    if (!repo.matches(REPO_PATTERN))
      throw w002(where + ": " + q(repo) + " is not an owner/repository");
    return repo;
  }

  static String encodeTag(String tag) { return tag.replace("+", "%2B"); }

  static Asset resolveRelease(String repo, String version) {
    if (repo.equals(UPSTREAM_REPO)) {
      String u = "https://github.com/" + UPSTREAM_REPO + "/releases/download/v"
          + canonical(version) + "/flix.jar";
      return new Asset("flix.jar", u);
    }
    String base = "https://github.com/" + repo + "/releases/download/"
          + encodeTag("v" + version) + "/";
    List<String> tried = new ArrayList<>();
    for (String name : List.of("flix-" + version + ".jar", "flix.jar")) {
      String u = base + encodeTag(name);
      tried.add(u);
      if (assetExists(u)) {
        validateUrl(u, repo + " release v" + version);
        return new Asset(name, u);
      }
    }
    throw w005("no compiler jar found in " + repo + " release " + q("v" + version)
        + "\n       tried " + String.join("\n             ", tried)
        + "\n       the version must match the tag exactly, build metadata included");
  }

  static HttpClient httpClient() {
    return HttpClient.newBuilder()
        .version(HttpClient.Version.HTTP_1_1)
        .followRedirects(HttpClient.Redirect.NORMAL)
        .connectTimeout(Duration.ofSeconds(30)).build();
  }

  static boolean assetExists(String url) {
    HttpClient client = httpClient();
    HttpRequest req = HttpRequest.newBuilder(URI.create(url))
        .method("HEAD", HttpRequest.BodyPublishers.noBody())
        .timeout(Duration.ofSeconds(60))
        .header("User-Agent", "flixw/" + WRAPPER_VERSION).build();
    try {
      HttpResponse<Void> res = client.send(req, HttpResponse.BodyHandlers.discarding());
      return res.statusCode() == 200 && "https".equals(res.uri().getScheme());
    } catch (IOException e) {
      return false;
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return false;
    }
  }

  record Pin(String repo, String version, String java, boolean clearJava, boolean refresh,
       String editorJar) {}

  static Pin parsePin(List<String> args, Lock existing) {
    String repo = null, version = null, java = null, clearJava = null, editorJar = null;
    boolean repoGiven = false, refresh = false;
    for (int i = 0; i < args.size(); i++) {
      String a = args.get(i);
      if (a.equals("--java")) {
        if (java != null || clearJava != null) throw w009("pin: two --java values given");
        if (i + 1 >= args.size())
          throw w002("pin: --java needs a version\n       for example:"
              + " ./flixw pin --java " + MIN_JAVA + "   (or --java none)");
        String v = args.get(++i);
        if (v.equals("none")) clearJava = "yes"; else { validateJavaPin(v, "pin"); java = v; }
      } else if (a.equals("--refresh")) {
        refresh = true;
      } else if (a.startsWith("--editor-jar=")) {
        if (editorJar != null) throw w009("pin: two --editor-jar values given");
        editorJar = a.substring("--editor-jar=".length());
        if (!editorJar.equals("copy") && !editorJar.equals("off"))
          throw w008("pin: --editor-jar must be 'copy' or 'off', not " + q(editorJar));
      } else if (a.startsWith("--")) {
        throw w008("pin: unknown option " + q(a) + "\n       " + PIN_USAGE);
      } else if (a.contains("/")) {
        if (repo != null) throw w009("pin: two repositories given");

        int at = a.indexOf('@');
        if (at < 0) {
          repo = checkRepo(a, "pin");
        } else {
          if (version != null) throw w009("pin: two versions given");
          repo = checkRepo(a.substring(0, at), "pin");
          version = a.substring(at + 1);
          if (version.isEmpty())
            throw w002("pin: " + q(a) + " -- a version must follow '@'"
                + "\n       for example: " + a.substring(0, at) + "@0.75.2");
        }
        repoGiven = true;
      } else {
        if (version != null) throw w009("pin: two versions given");
        version = a;
      }
    }
    if (refresh) {

      if (version != null || repoGiven || java != null || clearJava != null || editorJar != null)
        throw w008("pin: --refresh takes no other arguments -- it rewrites the lock"
            + " in the shape flixw " + WRAPPER_VERSION + " writes,"
            + "\n       from the values already in it, without moving the pin"
            + "\n       " + PIN_USAGE);
      if (existing == null)
        throw w002("pin: --refresh needs a lock that parses"
            + "\n       run: ./flixw pin <version>");
      return new Pin(null, null, null, false, true, null);
    }

    if (version == null && java == null && clearJava == null && editorJar == null)
      throw w002("pin: no version\n       " + PIN_USAGE);

    if (version == null && repoGiven)
      throw w002("pin: a repository needs a version -- changing it means fetching"
          + " that compiler\n       for example: ./flixw pin " + repo
          + " <version> --java " + (java == null ? MIN_JAVA + "" : java));
    if (version == null && existing == null)
      throw w002("pin: --java or --editor-jar needs an existing lock, or a compiler"
          + " version to write one\n       for example: ./flixw pin 0.75.2 --java "
          + MIN_JAVA);

    if (version != null) version = validateVersion(stripTagPrefix(version), "pin");
    if (repo == null) repo = existing != null && existing.repo() != null
               ? existing.repo() : UPSTREAM_REPO;
    return new Pin(repo, version, java, clearJava != null, false, editorJar);
  }

  static boolean insideCompilerCache(Path jar) {
    return jar.normalize().startsWith(cacheHome().resolve("compilers").normalize());
  }

  static void reportOverrideGap(Lock lock, Path jar) {
    if (lock == null || !insideCompilerCache(jar)) return;
    String got = sha256(jar);
    if (got.equals(lock.sha256()))
      w010("FLIX_JAR names flixw's own cache entry for the pinned compiler."
       + "\n          That is the jar flixw would have used anyway, and the name"
       + " changes at the next pin."
       + "\n          run: unset FLIX_JAR");
    else
      w010("FLIX_JAR names a compiler from flixw's cache that is NOT the pinned one."
       + "\n          override " + got.substring(0, 16) + "...  lock pins "
       + lock.sha256().substring(0, 16) + "..."
       + "\n          Cache names carry the digest, so this path is an earlier pin"
       + " left behind by a re-pin."
       + "\n          run: unset FLIX_JAR   (or ./flixw pin <that version> to make"
       + " it the pin)");
  }

  static Path compilerPath(Lock lock) {
    return cacheHome().resolve("compilers")
        .resolve("flix-" + canonical(lock.version()) + "-" + lock.sha256() + ".jar");
  }

  static void markUsed(String key) {
    String today = LocalDate.now(java.time.ZoneOffset.UTC).toString() + "\n";
    Path dir = cacheHome().resolve("usage");
    Path f = dir.resolve(key + ".used").normalize();
    if (!f.startsWith(dir)) return;
    try {
      if (Files.isRegularFile(f) && Files.readString(f, StandardCharsets.UTF_8).equals(today)) return;
      Files.createDirectories(f.getParent());
      writeAtomic(f, today);
    } catch (IOException ignored) { }
  }

  static void validateDistUrl() {
    String base = env("FLIX_DIST_URL");
    if (base == null) return;
    if (!base.startsWith("https://"))
      throw w008("FLIX_DIST_URL must be https, got " + q(redact(base)));
    URI u;
    try { u = URI.create(base); }
    catch (IllegalArgumentException e) {
      throw w008("FLIX_DIST_URL is not a valid URI: " + q(redact(base)));
    }

    if (u.getHost() == null || u.getHost().isBlank())
      throw w008("FLIX_DIST_URL has no host: " + q(redact(base)));
    if (u.getPath() != null && u.getPath().contains(".."))
      throw w008("FLIX_DIST_URL path must not contain '..': " + q(redact(base)));
  }

  static void validateUrl(String url, String where) {
    if (!url.startsWith("https://")) throw w002(where + ": url must be https, got " + q(url));
    URI u;
    try { u = URI.create(url); }
    catch (IllegalArgumentException e) { throw w002(where + ": url is not a valid URI: " + q(url)); }
    if (u.getHost() == null || u.getHost().isBlank())
      throw w002(where + ": url has no host: " + q(url));
    if (u.getPath() == null || u.getPath().isBlank() || u.getPath().contains(".."))
      throw w002(where + ": url has no usable path: " + q(url));
  }

  static String rewriteBase(String url) {
    String base = env("FLIX_DIST_URL");
    if (base == null) return url;
    validateDistUrl();
    int slash = url.indexOf('/', "https://".length());
    String tail = slash < 0 ? "" : url.substring(slash);
    return base.replaceAll("/+$", "") + tail;
  }

  static Path acquire(Lock lock) {
    Path jar = compilerPath(lock);
    if (!Files.isRegularFile(jar)) {
      Path dir = jar.getParent(), tmp;
      String url = rewriteBase(lock.url());
      System.err.println("flixw: downloading Flix " + lock.version() + " from " + redact(url));
      try {
        Files.createDirectories(dir);
        tmp = Files.createTempFile(dir, ".flix-", ".part");
      } catch (IOException e) {
        throw w007("cannot prepare cache " + dir + ": " + why(e));
      }
      try {
        download(url, tmp);
        String got = sha256(tmp);
        if (!got.equals(lock.sha256()))
          throw w006("digest mismatch for " + redact(lock.url())
              + "\n       expected " + lock.sha256() + "\n       actual   " + got);
        try { Files.move(tmp, jar, StandardCopyOption.ATOMIC_MOVE); }
        catch (IOException e) {
          if (!Files.isRegularFile(jar))
            throw w007("cannot install " + jar + ": " + e.getMessage());
        }
      } finally { try { Files.deleteIfExists(tmp); } catch (IOException ignored) {} }
    }
    tr("compiler present");
    String got = sha256(jar);
    tr("sha256 done");
    if (!got.equals(lock.sha256()))
      throw w006("cached " + jar + " no longer matches its pinned digest");

    writePinRecord(lock.sha256(), lock.repo() == null ? UPSTREAM_REPO : lock.repo(), lock.version());
    markUsed("compiler/" + lock.sha256());
    return jar;
  }

  static void download(String url, Path dest) {
    if (!url.startsWith("https://")) throw w005("refusing non-https url " + redact(url));
    HttpClient client = httpClient();
    HttpRequest req = HttpRequest.newBuilder(URI.create(url))
        .timeout(Duration.ofMinutes(10))
        .header("User-Agent", "flixw/" + WRAPPER_VERSION).build();
    try {
      HttpResponse<Path> res = client.send(req, HttpResponse.BodyHandlers.ofFile(dest));
      if (!"https".equals(res.uri().getScheme()))
        throw w005("refusing a redirect off https: " + redact(res.uri().toString()));
      if (res.statusCode() != 200)
        throw w005("HTTP " + res.statusCode() + " for " + redact(url)
            + "\n       check that flix.toml names a published release.");
    } catch (IOException e) {
      throw w005("download failed: " + redact(url) + "\n       " + e.getMessage());
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw w005("download interrupted");
    }
  }

  static String runCapture(List<String> cmd, Duration timeout, int cap) throws IOException {
    Process p = new ProcessBuilder(cmd).redirectErrorStream(true).start();
    String[] box = new String[1];
    Thread readerThread = null;
    try {
      p.getOutputStream().close();
      Thread reader = new Thread(() -> {
        ByteArrayOutputStream sink = new ByteArrayOutputStream();
        try (InputStream in = p.getInputStream()) {
          byte[] buf = new byte[1 << 16];
          int total = 0, n;
          while (total < cap && (n = in.read(buf)) > 0) {
            sink.write(buf, 0, Math.min(n, cap - total));
            total += n;
          }

          if (total >= cap) { p.destroy(); p.destroyForcibly(); }
        } catch (IOException ignored) {

        } finally {

          box[0] = sink.toString(StandardCharsets.UTF_8);
        }
      }, "flixw-capture");
      reader.setDaemon(true);
      readerThread = reader;
      reader.start();
      if (!p.waitFor(timeout.toMillis(), TimeUnit.MILLISECONDS)) return null;
      reader.join(2000);

      if (reader.isAlive()) {
        try { p.getInputStream().close(); } catch (IOException ignored) { }
        reader.join(1000);
      }
      return box[0];
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return null;
    } finally {

      p.descendants().forEach(ProcessHandle::destroyForcibly);
      if (p.isAlive()) {
        p.destroyForcibly();
        try { p.waitFor(5, TimeUnit.SECONDS); }
        catch (InterruptedException e) { Thread.currentThread().interrupt(); }
      }
      if (readerThread != null) {
        try { readerThread.join(2000); }
        catch (InterruptedException e) { Thread.currentThread().interrupt(); }
      }
    }
  }

  record Jvm(Path exe, int feature, String how) {}

  static boolean diagnostic(String verb) {

    return verb != null
       && List.of("info", "doctor", "validate", "help", "--help", "-h").contains(verb);
  }

  static Jvm runningJvm() {
    Path exe = ProcessHandle.current().info().command().map(Paths::get)
           .orElseGet(() -> exeIn(System.getProperty("java.home")));
    return new Jvm(exe, Runtime.version().feature(), "running JVM");
  }

  static Path exeIn(String home) {
    return Paths.get(home, "bin", isWindows() ? "java.exe" : "java");
  }

  static int probe(Path exe) {
    Integer f = feature(probeVersion(exe));
    return f == null ? -1 : f;
  }

  static String probeVersion(Path exe) {
    Path home = exe.getParent() == null ? null : exe.getParent().getParent();
    if (home != null) {
      Path rel = home.resolve("release");
      if (Files.isRegularFile(rel)) {
        try {
          String t = Files.readString(rel, StandardCharsets.UTF_8);
          Matcher m = Pattern.compile("(?m)^JAVA_VERSION=\"([^\"]+)\"").matcher(t);
          if (m.find() && feature(m.group(1)) != null) return m.group(1);
        } catch (IOException ignored) { }
      }
    }
    try {

      String out = runCapture(List.of(exe.toString(), "-XshowSettings:properties", "-version"),
                  PROBE_TIMEOUT, 1 << 18);
      if (out != null) {

        Matcher m = Pattern.compile("(?m)^\\s*java\\.version = ([0-9][0-9.+_-]*)").matcher(out);
        if (m.find() && feature(m.group(1)) != null) return m.group(1);
        m = Pattern.compile("java\\.specification\\.version = ([0-9.]+)").matcher(out);
        if (m.find() && feature(m.group(1)) != null) return m.group(1);
      }
    } catch (Exception ignored) { }
    return null;
  }

  static boolean satisfiesJavaPin(String pin, String version) {
    if (pin == null) return true;
    if (version == null) return false;
    if (version.equals(pin)) return true;
    return version.startsWith(pin) && version.charAt(pin.length()) == '.';
  }

  static void validateJavaPin(String v, String where) {
    if (!v.matches(JAVA_PIN_PATTERN))
      throw w002(where + ": java version " + q(v) + " is not a dotted number"
          + "\n       write a feature release (21) or an exact one (21.0.12)");
    Integer f = feature(v);
    if (f == null || f < MIN_JAVA)
      throw w002(where + ": java " + q(v) + " is below Java " + MIN_JAVA
          + ", which the compiler needs");
  }

  static Integer feature(String v) {
    Matcher m = Pattern.compile("^([0-9]+)").matcher(v);
    return m.find() ? Integer.parseInt(m.group(1)) : null;
  }

  static boolean strictJava() { return env("FLIXW_STRICT_JAVA") != null; }

  static boolean acceptable(int f, String source) {
    if (f < 0) return false;
    if (f < MIN_JAVA) return false;
    if (f > TESTED_CEILING) {
      if (strictJava()) return false;
      w011("Java " + f + " (" + source + ") is above the tested ceiling "
       + TESTED_CEILING + "; proceeding. Set FLIXW_STRICT_JAVA=1 to make this fatal.");
    }
    return true;
  }

  static Jvm chooseInstall(List<Jvm> candidates, boolean strict) {
    Jvm tested = null, above = null;
    for (Jvm c : candidates) {
      if (c.feature() < MIN_JAVA) continue;
      if (c.feature() <= TESTED_CEILING) {
        if (tested == null || c.feature() > tested.feature()) tested = c;
      } else if (!strict) {
        if (above == null || c.feature() < above.feature()) above = c;
      }
    }
    return tested != null ? tested : above;
  }

  static Jvm selectJava(String pin) {
    for (String var : new String[] { "FLIX_JAVA_HOME", "JAVA_HOME" }) {
      String h = env(var);
      if (h == null) continue;
      Path exe = exeIn(h);
      if (!Files.isRegularFile(exe))
        throw w004(var + "=" + h + " has no " + exe.getFileName() + " at " + exe);
      if (!Files.isExecutable(exe))
        throw w004(var + "=" + h + ": " + exe + " is not executable");
      String full = probeVersion(exe);
      int f = probe(exe);
      if (!acceptable(f, var))
        throw w004(var + "=" + h + " is Java " + (f < 0 ? "unidentifiable" : f)
            + "; flixw needs [" + MIN_JAVA + ", " + TESTED_CEILING + "]"
            + (strictJava() ? " (FLIXW_STRICT_JAVA is set)" : ""));

      if (!satisfiesJavaPin(pin, full))
        throw w004(var + "=" + h + " is Java " + (full == null ? "unidentifiable" : full)
            + ", but " + WRAPPER_DIR + "/lock.toml pins java " + pin
            + "\n       unset " + var + ", or run: ./flixw pin --java "
            + (full == null ? "<version>" : full));
      return markJvmUse(new Jvm(exe, f, var));
    }
    int self = Runtime.version().feature();
    Path selfExe = ProcessHandle.current().info().command()
        .map(Paths::get).orElse(exeIn(System.getProperty("java.home")));
    if (acceptable(self, "running JVM")
      && satisfiesJavaPin(pin, Runtime.version().toString().split("[+-]")[0]))
      return markJvmUse(new Jvm(selfExe, self, "running JVM"));

    List<Jvm> found = new ArrayList<>();
    Path mine = installedJdk();
    if (mine != null) {
      int f = probe(mine);
      if (f >= MIN_JAVA && satisfiesJavaPin(pin, probeVersion(mine)))
        found.add(new Jvm(mine, f, "installed by flixw"));
    }
    for (Path cand : knownInstalls()) {
      int f = probe(cand);
      if (f >= MIN_JAVA && satisfiesJavaPin(pin, probeVersion(cand)))
        found.add(new Jvm(cand, f, "known installation"));
    }
    Jvm pick = chooseInstall(found, strictJava());
    if (pick != null) return markJvmUse(pick);
    return noJavaFound(self, pin);
  }

  static Jvm markJvmUse(Jvm jvm) {
    for (Path dir : cachedJdkDirs())
      if (jvm.exe().normalize().startsWith(dir.normalize()))
        markUsed("jdk/" + dir.getFileName());
    return jvm;
  }

  static List<Path> knownInstalls() {
    List<Path> out = new ArrayList<>();
    List<Path> roots = new ArrayList<>();
    String home = System.getProperty("user.home", "");
    if (isMac()) {
      roots.add(Paths.get("/Library/Java/JavaVirtualMachines"));
      roots.add(Paths.get(home, "Library/Java/JavaVirtualMachines"));
      roots.add(Paths.get("/opt/homebrew/opt"));
      roots.add(Paths.get("/usr/local/opt"));
    } else if (!isWindows()) {
      roots.add(Paths.get("/usr/lib/jvm"));
      roots.add(Paths.get("/usr/lib64/jvm"));
      roots.add(Paths.get("/usr/java"));
      roots.add(Paths.get("/opt/java"));
    } else {
      roots.add(Paths.get("C:\\Program Files\\Java"));
      roots.add(Paths.get("C:\\Program Files\\Eclipse Adoptium"));
      roots.add(Paths.get("C:\\Program Files\\Microsoft"));
      roots.add(Paths.get("C:\\Program Files\\Amazon Corretto"));
      roots.add(Paths.get("C:\\Program Files\\Zulu"));
      roots.add(Paths.get("C:\\Program Files (x86)\\Java"));
      roots.add(Paths.get(home, "scoop", "apps"));
      String localApp = env("LOCALAPPDATA");
      if (localApp != null) roots.add(Paths.get(localApp, "Programs"));

      String progData = env("ProgramData");
      if (progData != null) {
        Path lib = Paths.get(progData, "chocolatey", "lib");
        if (Files.isDirectory(lib)) {
          try (var s = Files.list(lib)) {
            s.sorted().map(pkg -> pkg.resolve("tools"))
                 .filter(Files::isDirectory).forEach(roots::add);
          } catch (IOException ignored) { }
        }
      }
    }

    for (String vm : new String[] { ".sdkman/candidates/java", ".asdf/installs/java",
                    ".local/share/mise/installs/java", ".jenv/versions",
                    ".gradle/jdks" })
      roots.add(Paths.get(home, vm.split("/")));

    String exe = isWindows() ? "java.exe" : "java";
    for (Path r : roots) {
      if (!Files.isDirectory(r)) continue;

      Path self = r.resolve("bin").resolve(exe);
      if (Files.isExecutable(self)) out.add(self);
      try (var s = Files.list(r)) {
        s.sorted().forEach(d -> {
          for (Path h : new Path[] { d, d.resolve("Contents/Home"),
                       d.resolve("libexec/openjdk.jdk/Contents/Home"),
                       d.resolve("current") }) {
            Path e = h.resolve("bin").resolve(exe);
            if (Files.isExecutable(e)) { out.add(e); return; }
          }
        });
      } catch (IOException ignored) { }
    }
    return out;
  }

  static final int METADATA_CAP = 1 << 21;

  static String httpGet(String url) {
    HttpClient client = httpClient();
    HttpRequest req = HttpRequest.newBuilder(URI.create(url))
        .timeout(Duration.ofSeconds(60))
        .header("User-Agent", "flixw/" + WRAPPER_VERSION).build();
    try {

      HttpResponse<InputStream> res =
        client.send(req, HttpResponse.BodyHandlers.ofInputStream());
      if (!"https".equals(res.uri().getScheme()))
        throw w005("refusing a redirect off https: " + redact(res.uri().toString()));
      if (res.statusCode() != 200)
        throw w005("HTTP " + res.statusCode() + " from " + redact(url));
      ByteArrayOutputStream sink = new ByteArrayOutputStream();
      try (InputStream in = res.body()) {
        byte[] buf = new byte[1 << 16];
        int total = 0, n;
        while (total < METADATA_CAP && (n = in.read(buf)) > 0) {
          sink.write(buf, 0, Math.min(n, METADATA_CAP - total));
          total += n;
        }
        if (total >= METADATA_CAP)
          throw w005("metadata from " + redact(url) + " exceeded "
              + (METADATA_CAP >> 10) + "KiB");
      }
      return sink.toString(StandardCharsets.UTF_8);
    } catch (IOException e) {
      throw w005("cannot reach " + redact(url) + "\n       " + e.getMessage());
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw w005("metadata request interrupted");
    }
  }

  static Path installedJdk() {
    Path marker = cacheHome().resolve("jdks").resolve("default");
    try {
      if (!Files.isRegularFile(marker)) return null;
      Path exe = Paths.get(Files.readString(marker, StandardCharsets.UTF_8).strip())
              .toAbsolutePath().normalize();

      Path jdks = cacheHome().resolve("jdks").toAbsolutePath().normalize();
      if (!exe.startsWith(jdks) || !Files.isRegularFile(exe)) return null;

      if (!exe.toRealPath().startsWith(jdks.toRealPath())) return null;
      return exe;
    } catch (IOException | RuntimeException e) { return null; }
  }

  static Path findJavaUnder(Path root) {
    String want = isWindows() ? "java.exe" : "java";
    try (var s = Files.walk(root, 6)) {
      return s.filter(x -> x.getFileName().toString().equals(want)
               && x.getParent() != null
               && x.getParent().getFileName().toString().equals("bin")
               && Files.isRegularFile(x)
               && (isWindows() || Files.isExecutable(x)))
          .findFirst().orElse(null);
    } catch (IOException e) { return null; }
  }

  static void jdkInstructions(int want) {
    System.err.println("       install a JDK " + want
            + (want == MIN_JAVA ? "+" : "") + " and re-run, for example:");
    if (isMac()) {
      System.err.println("         brew install temurin@" + want);
    } else if (isWindows()) {
      System.err.println("         winget install EclipseAdoptium.Temurin." + want + ".JDK");
      System.err.println("         scoop install temurin" + want + "-jdk");
    } else {
      System.err.println("         apt install temurin-" + want + "-jdk         (Debian, Ubuntu)");
      System.err.println("         dnf install temurin-" + want + "-jdk         (Fedora, RHEL)");
      System.err.println("         pacman -S jdk" + want + "-openjdk           (Arch)");
    }
    System.err.println("         or https://adoptium.net/temurin/releases/?version=" + want);
    System.err.println("       then set JAVA_HOME, or put its bin directory on PATH.");
  }

  static boolean javaPinAvailable(String pin) {
    if (pin == null) return true;
    if (satisfiesJavaPin(pin, Runtime.version().toString().split("[+-]")[0])) return true;
    Path mine = installedJdk();
    if (mine != null && satisfiesJavaPin(pin, probeVersion(mine))) return true;
    for (Path cand : knownInstalls())
      if (satisfiesJavaPin(pin, probeVersion(cand))) return true;
    return false;
  }

  static Jvm noJavaFound(int self, String pin) {

    int want = pin == null ? MIN_JAVA : feature(pin);
    System.err.println(pin == null
      ? "FLIXW003: no Java in [" + MIN_JAVA + ", " + TESTED_CEILING
       + "] found; this JVM is " + self
      : "FLIXW003: no Java " + pin + " found, which " + WRAPPER_DIR
       + "/lock.toml pins; this JVM is " + self);
    jdkInstructions(want);
    System.err.println("       or run: ./flixw wrapper --install-jdk   (fetches a verified"
            + " Temurin " + want + " into flixw's own cache)");
    throw w003("no usable Java; see the instructions above");
  }

  static void installJdkVerb(List<String> argv) {
    if (argv.size() > 1)
      throw w008(wrapperUsage("'--install-jdk' takes no arguments"));

    Integer want = null;
    try {
      Path lf = lockPath(findRoot(wrapperAnchor()));
      if (Files.isRegularFile(lf)) {
        String j = readLock(lf).java();
        if (j != null) want = feature(j);
      }
    } catch (Fail ignored) { }
    Path exe = runJdkAsset(want == null ? MIN_JAVA : want);
    int f = probe(exe);
    if (f < MIN_JAVA)
      throw w003("the JDK just installed reports Java " + f + ", below " + MIN_JAVA);
    System.out.println(exe);
    System.err.println("flixw: Temurin Java " + f + " is installed.");
    System.err.println("       flixw will find it from now on; export JAVA_HOME="
            + exe.getParent().getParent() + " to use it elsewhere.");
  }

  static Path runJdkAsset(int feature) {
    Path asset = ensureAsset(JDK_ASSET);
    Path result = null;
    try {

      result = Files.createTempFile("flixw-jdk-", ".path");
      int rc = runAsset(asset, null,
        List.of(Integer.toString(feature), cacheHome().toString(), result.toString()));

      if (rc != 0) System.exit(rc);
      String out = Files.readString(result).strip();
      if (out.isEmpty()) throw w003("the JDK provisioner named no java");
      return Paths.get(out);
    } catch (IOException e) {
      throw w005("cannot run " + asset + ": " + why(e));
    } finally {
      if (result != null) { try { Files.deleteIfExists(result); } catch (IOException ignored) { } }
    }
  }

  static final Pattern UNSAFE = Pattern.compile(
    "^(-jar|-cp|-classpath|--class-path|--module-path|-p|-javaagent:.*|-agentlib:.*|"
   + "-agentpath:.*|@.*|-XX:OnError=.*|-XX:OnOutOfMemoryError=.*|-XX:\\+?UnlockDiagnosticVMOptions|"
   + "-XX:Flags=.*|--patch-module.*|-Xbootclasspath.*)$");

  static List<String> jvmOpts() {
    String raw = env("FLIX_JVM_OPTS");
    if (raw == null) return List.of();
    List<String> toks = tokenize(raw);
    boolean unsafeOk = env("FLIXW_UNSAFE_JVM_OPTS") != null;
    for (String t : toks) {
      if (!t.startsWith("-")) throw w008("FLIX_JVM_OPTS: " + q(t) + " is not an option");
      if (UNSAFE.matcher(t).matches() && !unsafeOk)
        throw w008("FLIX_JVM_OPTS: " + q(t) + " needs FLIXW_UNSAFE_JVM_OPTS=1");
    }
    return toks;
  }

  static List<String> tokenize(String s) {
    List<String> out = new ArrayList<>();
    StringBuilder cur = new StringBuilder();
    boolean has = false; char quote = 0;
    for (int i = 0; i < s.length(); i++) {
      char c = s.charAt(i);
      if (quote != 0) {
        if (c == quote) quote = 0;
        else if (c == '\\' && quote == '"' && i + 1 < s.length()) cur.append(s.charAt(++i));
        else cur.append(c);
      } else if (c == '\'' || c == '"') { quote = c; has = true; }
      else if (c == '\\' && i + 1 < s.length()) { cur.append(s.charAt(++i)); has = true; }
      else if (Character.isWhitespace(c)) {
        if (has || cur.length() > 0) { out.add(cur.toString()); cur.setLength(0); has = false; }
      }
      else { cur.append(c); has = true; }
    }
    if (quote != 0) throw w008("FLIX_JVM_OPTS: unterminated " + quote + " quote");
    if (has || cur.length() > 0) out.add(cur.toString());
    return out;
  }

  static Path wrapperAnchor() {
    Path self = sourceLaunchPath();
    if (self == null) {
      String src = env("FLIXW_SOURCE");
      if (src != null) self = Paths.get(src);
      else {
        try {
          self = Paths.get(flixw.class.getProtectionDomain().getCodeSource()
                  .getLocation().toURI());
        } catch (Exception ignored) { }
      }
    }
    if (self == null) return Paths.get("").toAbsolutePath();
    try { self = resolveLinkChain(self.toAbsolutePath()); } catch (IOException ignored) { }
    Path dir = Files.isDirectory(self) ? self : self.getParent();

    if (dir != null && dir.getFileName() != null
      && dir.getFileName().toString().equals(WRAPPER_DIR)) return dir.getParent();
    return dir == null ? Paths.get("").toAbsolutePath() : dir;
  }

  static Path resolveLinkChain(Path p) throws IOException {
    Path cur = p;
    for (int i = 0; i < 40 && Files.isSymbolicLink(cur); i++) {
      Path t = Files.readSymbolicLink(cur);
      cur = t.isAbsolute() ? t : cur.getParent().resolve(t).normalize();
    }
    return cur;
  }

  static Path findRoot(Path anchor) {
    String o = env("FLIX_PROJECT_ROOT");
    if (o != null) {
      Path r = Paths.get(o).toAbsolutePath().normalize();
      if (!Files.isDirectory(r))
        throw w001("FLIX_PROJECT_ROOT=" + o + " is not a directory");
      return r;
    }
    Path cwd = Paths.get("").toAbsolutePath().normalize();
    if (!cwd.startsWith(anchor))
      throw w001("this wrapper belongs to " + anchor + ", but the current directory is "
          + cwd + "\n       cd into the project, or set FLIX_PROJECT_ROOT explicitly");
    for (Path p = cwd; p != null && p.startsWith(anchor); p = p.getParent())
      if (Files.isRegularFile(p.resolve("flix.toml"))) return p;

    return anchor;
  }

  static Path verbsFile(Path jar, String identity) {
    return cacheHome().resolve("verbs").resolve(identity + ".verbs");
  }

  static Path helpFile(String identity) {
    return cacheHome().resolve("verbs").resolve(identity + ".help");
  }

  static Path helpMetaFile(String identity) {
    return cacheHome().resolve("verbs").resolve(identity + ".helpmeta");
  }

  static void writeHelpRecord(String identity, String help) {
    try {
      Files.createDirectories(helpFile(identity).getParent());
      writeAtomic(helpFile(identity), help);
      String reported = parseReportedVersion(help);
      writeAtomic(helpMetaFile(identity),
         "reported_version=" + (reported == null ? "unknown" : reported)
        + "\ncontent_sha256=" + sha256(help.getBytes(StandardCharsets.UTF_8))
        + "\ncaptured_at=" + LocalDate.now(java.time.ZoneOffset.UTC) + "\n");
    } catch (IOException e) {
      tr("cannot cache help at " + helpFile(identity) + ": " + e.getMessage());
    }
  }

  static String verbIdentity(Path jar, Lock lock, boolean override) {
    if (!override) return lock.sha256();
    try {
      return "override-" + sha256((jar.toAbsolutePath() + "|" + Files.size(jar) + "|"
          + Files.getLastModifiedTime(jar).toMillis()).getBytes(StandardCharsets.UTF_8));
    } catch (IOException e) {
      return "override-" + sha256(jar.toAbsolutePath().toString().getBytes(StandardCharsets.UTF_8));
    }
  }

  static List<String> verbs(Path javaExe, Path jar, String identity) {
    Path vf = verbsFile(jar, identity);
    try {

      if (Files.isRegularFile(vf) && Files.isRegularFile(helpFile(identity))
        && Files.isRegularFile(helpMetaFile(identity))) {
        List<String> v = new ArrayList<>(Files.readAllLines(vf, StandardCharsets.UTF_8));
        v.removeIf(String::isBlank);
        if (!v.isEmpty()) return v;
      }
    } catch (IOException ignored) { }
    List<String> v;
    String help;
    try {
      help = captureHelp(javaExe, jar);

      writeHelpRecord(identity, help);
      v = captureVerbs(help, jar);
    } catch (Fail f) {

      w010(f.getMessage().split("\n")[0]
       + "\n          using the built-in verb table for Flix 0.75.x;"
       + " compiler-first dispatch still applies");
      return BUILTIN_VERBS;
    }
    try {
      Files.createDirectories(vf.getParent());
      Path tmp = Files.createTempFile(vf.getParent(), ".verbs-", ".part");
      Files.writeString(tmp, String.join("\n", v) + "\n", StandardCharsets.UTF_8);
      Files.move(tmp, vf, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
    } catch (IOException e) {

      tr("cannot cache verbs at " + vf + ": " + e.getMessage());
    }
    return v;
  }

  record PinRecord(String repo, String version) {}

  static Path pinRecordFile(String identity) {
    return cacheHome().resolve("verbs").resolve(identity + ".pin");
  }

  static PinRecord cachedPinRecord(String identity) {
    try {
      List<String> lines = Files.readAllLines(pinRecordFile(identity), StandardCharsets.UTF_8);
      return lines.size() < 2 ? null : new PinRecord(lines.get(0), lines.get(1));
    } catch (IOException e) { return null; }
  }

  static void writePinRecord(String identity, String repo, String version) {
    Path f = pinRecordFile(identity);
    try {
      Files.createDirectories(f.getParent());
      Path tmp = Files.createTempFile(f.getParent(), ".pin-", ".part");
      Files.writeString(tmp, repo + "\n" + version + "\n", StandardCharsets.UTF_8);
      Files.move(tmp, f, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
    } catch (IOException e) {
      tr("cannot cache the pin record at " + f + ": " + e.getMessage());
    }
  }

  static String captureHelp(Path javaExe, Path jar) {
    String out;
    try {

      out = runCapture(List.of(javaExe.toString(), "-jar", jar.toString(), "--help"),
              HELP_TIMEOUT, HELP_CAP);
    } catch (IOException e) {
      throw w009("cannot run `flix --help`: " + e.getMessage());
    }
    if (out == null)
      throw w009("`flix --help` did not finish within " + HELP_TIMEOUT.toSeconds() + "s");

    return out.replace("\r\n", "\n").replace('\r', '\n');
  }

  static List<String> captureVerbs(String out, Path jar) {
    List<String> verbs = parseVerbs(out);
    if (verbs.size() < 3)
      throw w009("cannot parse verbs from `flix --help` of " + jar
          + " (got " + verbs.size() + " candidate(s))");
    return verbs;
  }

  static final Pattern VERSION_TOKEN = Pattern.compile(
    "(?<![0-9A-Za-z.+-])(" + SEMVERISH.pattern() + ")(?![0-9A-Za-z.+-])");

  static String parseReportedVersion(String help) {
    int seen = 0;
    for (String line : help.split("\r?\n")) {
      if (line.isBlank()) continue;
      if (++seen > HEADER_LINES) return null;
      Matcher m = VERSION_TOKEN.matcher(line);
      if (m.find()) return m.group(1);
    }
    return null;
  }

  static final int HEADER_LINES = 3;

  static String captureReportedVersion(Path jar, String javaPin) {
    try {
      Jvm jvm = selectJava(javaPin);
      return parseReportedVersion(captureHelp(jvm.exe(), jar));
    } catch (RuntimeException e) {
      tr("cannot ask the compiler its version: " + e.getMessage());
      return null;
    }
  }

  static void reportVersionGap(String lead, String pinned, String reported) {
    if (reported == null || canonical(reported).equals(canonical(pinned))) return;
    w010(lead + " reports itself as " + q(reported) + ", but the lock pins " + q(pinned)
     + "\n          the digest still pins these exact bytes; what is in doubt is the"
     + " version they were published under"
     + "\n          run: ./flixw pin " + reported + "   (to pin what is actually here)");
  }

  static final Pattern COMMAND_ENTRY = Pattern.compile("^ {2}([a-z][a-z0-9_-]*)(?:\\s|$)");

  static List<String> parseVerbs(String out) {
    Set<String> set = new LinkedHashSet<>();

    Matcher usage = Pattern.compile("(?ms)^Usage:.*?\\[([a-z0-9|_\\-\\s]+)\\]").matcher(out);
    if (usage.find()) {
      String list = usage.group(1).replaceAll("\\s", "");

      if (list.contains("|"))
        for (String s : list.split("\\|")) if (!s.isBlank()) set.add(s);
    }

    Matcher cmd = Pattern.compile("(?m)^Command:\\s+([A-Za-z][A-Za-z0-9_-]*)").matcher(out);
    while (cmd.find()) set.add(cmd.group(1));

    boolean inBlock = false;
    for (String line : out.split("\n", -1)) {
      if (!inBlock) { inBlock = line.startsWith("Commands:"); continue; }
      Matcher m = COMMAND_ENTRY.matcher(line);
      if (m.find()) set.add(m.group(1));
      else if (!line.isBlank() && !line.startsWith("   ")) break;
    }

    return new ArrayList<>(set);
  }

  static Path stage0Dir(String srcHash) {
    return cacheHome().resolve("stage0").resolve(srcHash);
  }

  static int runAsset(Path asset, Path classpath, List<String> args) {
    Path classes = compileAsset(asset, classpath);
    if (classes == null)
      throw w005("cannot compile " + asset.getFileName() + "\n"
          + "       this Java runtime has no compiler, so flixw cannot run its"
          + " companion assets\n"
          + "       run: ./flixw wrapper --install-jdk   (or use a JDK, not a JRE)");
    List<URL> urls = new ArrayList<>();
    try {
      urls.add(classes.toUri().toURL());
      if (classpath != null) urls.add(classpath.toUri().toURL());
      try (URLClassLoader loader = new URLClassLoader("flixw-asset",
          urls.toArray(new URL[0]), ClassLoader.getPlatformClassLoader())) {
        java.lang.reflect.Method run = loader.loadClass(assetMainClass(asset))
          .getMethod("run", String[].class);

        run.setAccessible(true);
        Object rc = run.invoke(null, (Object) args.toArray(new String[0]));
        return rc instanceof Integer i ? i : 0;
      }
    } catch (ReflectiveOperationException | IOException | LinkageError e) {
      throw w005("cannot run " + asset.getFileName() + ": " + e);
    }
  }

  static String assetMainClass(Path asset) {
    return asset.getFileName().toString().replace("-", "").replace(".java", "");
  }

  static Path compiledAssetDir(String srcHash) {

    return cacheHome().resolve("assets").resolve(srcHash + "-" + SOURCE_FLOOR);
  }

  static Path compileAsset(Path asset, Path classpath) {
    byte[] bytes;
    try { bytes = Files.readAllBytes(asset); } catch (IOException e) { return null; }
    Path dir = compiledAssetDir(sha256(bytes));
    if (Files.isRegularFile(dir.resolve(assetMainClass(asset) + ".class"))) return dir;
    javax.tools.JavaCompiler jc = javax.tools.ToolProvider.getSystemJavaCompiler();
    if (jc == null) { tr("no javac in this runtime; source-launching " + asset); return null; }
    Path tmp = null;
    boolean cacheable = true;
    try {
      try {
        Files.createDirectories(dir.getParent());
        tmp = Files.createTempDirectory(dir.getParent(), ".asset-");
      } catch (IOException e) {

        cacheable = false;
        tmp = Files.createTempDirectory("flixw-asset-");
      }

      List<String> args = new ArrayList<>(List.of("-d", tmp.toString(), "--release", String.valueOf(SOURCE_FLOOR)));
      if (classpath != null) { args.add("-cp"); args.add(classpath.toString()); }
      args.add(asset.toString());
      if (jc.run(null, java.io.OutputStream.nullOutputStream(),
           java.io.OutputStream.nullOutputStream(),
           args.toArray(new String[0])) != 0) return null;
      if (!cacheable) {
        Path ephemeral = tmp;
        tmp = null;
        Runtime.getRuntime().addShutdownHook(new Thread(() -> deleteTree(ephemeral)));
        return ephemeral;
      }
      try { Files.move(tmp, dir, StandardCopyOption.ATOMIC_MOVE); tmp = null; }
      catch (IOException e) { if (!Files.isDirectory(dir)) return null; }
      return dir;
    } catch (IOException e) {
      tr("cannot compile " + asset + ": " + e.getMessage());
      return null;
    } finally {
      if (tmp != null) deleteTree(tmp);
    }
  }

  static void selfCompile(Path source) {
    if (source == null) return;
    byte[] bytes;
    try { bytes = Files.readAllBytes(source); } catch (IOException e) { return; }
    Path dir = stage0Dir(sha256(bytes));
    if (Files.isRegularFile(dir.resolve("flixw.class"))) return;
    javax.tools.JavaCompiler jc = javax.tools.ToolProvider.getSystemJavaCompiler();
    if (jc == null) { tr("no javac in this runtime; staying on the source path"); return; }
    Path tmp = null;
    try {
      Path parent = Files.createDirectories(dir.getParent());

      try { parent.toFile().setReadable(false, false); parent.toFile().setReadable(true, true);
         parent.toFile().setWritable(false, false); parent.toFile().setWritable(true, true);
         parent.toFile().setExecutable(false, false); parent.toFile().setExecutable(true, true);
      } catch (SecurityException ignored) { }
      tmp = Files.createTempDirectory(parent, ".stage0-");

      int rc = jc.run(null, java.io.OutputStream.nullOutputStream(),
              java.io.OutputStream.nullOutputStream(),
              "-d", tmp.toString(), "-nowarn",
              "--release", String.valueOf(MIN_JAVA), source.toString());
      if (rc != 0) { tr("self-compile failed rc=" + rc); return; }
      Files.writeString(tmp.resolve("source.path"), source.toAbsolutePath() + "\n");
      Files.move(tmp, dir, StandardCopyOption.ATOMIC_MOVE);
      tmp = null;
      tr("self-compiled stage 0 into " + dir);
    } catch (IOException e) {
      tr("self-compile skipped: " + e.getMessage());
    } finally {

      if (tmp != null) deleteTree(tmp);
    }
  }

  static void deleteTree(Path p) {
    try (var s = Files.walk(p)) {
      s.sorted(java.util.Comparator.reverseOrder()).forEach(x -> {
        try { Files.deleteIfExists(x); } catch (IOException ignored) { }
      });
    } catch (IOException ignored) { }
  }

  static void wrapperVerb(String verb, List<String> rest, Path root, Lock lock, Path jar,
              Jvm jvm, List<String> compilerVerbs, String verbId) {
    switch (verb) {
      case "pin" -> {
        if (wantsHelp(rest)) { System.out.println(PIN_USAGE); return; }
        if (rest.isEmpty())
          throw w009(PIN_USAGE);
        pin(root, parsePin(rest, lock));
      }

      case "help" -> {
        if (localHelpTopic(rest)) return;
        if (!rest.isEmpty())
          throw w008("./flixw help: unknown argument " + q(rest.get(0))
              + "\n       usage: ./flixw help");
        helpTopic(List.of(), root, lock, jar, jvm,
             compilerVerbs == null ? List.of() : compilerVerbs, verbId, List.of(), true);
      }

      case "info" -> {
        if (wantsHelp(rest)) { System.out.println(INFO_USAGE); return; }
        boolean verbose = rest.contains("--verbose") || rest.contains("-v");
        for (String a : rest)
          if (!a.equals("--verbose") && !a.equals("-v"))
            throw w008("./flixw info: unknown option " + q(a) + "\n       " + INFO_USAGE);
        report(root, lock, jar, jvm, compilerVerbs, askedVersion(lock));
        if (verbose) { System.out.println(); listCache(lock, jvm); }
      }
      case "validate" -> {
        if (wantsHelp(rest)) { System.out.println(VALIDATE_USAGE); return; }

        if (!rest.isEmpty())
          throw w008("./flixw validate: unknown argument " + q(rest.get(0))
              + "\n       " + VALIDATE_USAGE);
        int bad = check(root, lock, jar, jvm);
        if (bad > 0) throw w009(bad + " validation failure(s)");
      }
      case "doctor" -> {
        if (wantsHelp(rest)) { System.out.println(DOCTOR_USAGE); return; }
        boolean fix = rest.contains("--fix");
        for (String a : rest)
          if (!a.equals("--fix"))
            throw w008("./flixw doctor: unknown option " + q(a) + "\n       " + DOCTOR_USAGE);

        if (fix) {
          updateWrapper(root);
          if (jar != null && Files.isRegularFile(jar)) maintainEditorJar(root, jar, null);
          System.out.println();
        }
        report(root, lock, jar, jvm, compilerVerbs, askedVersion(lock));
        System.out.println();
        int bad = check(root, lock, jar, jvm);
        if (bad > 0)
          throw w009(bad + " problem(s); ./flixw doctor --fix repairs the wrapper"
              + " files, ./flixw pin <version> repairs a drifted lock");
      }

      case "plugin" -> {
        if (rest.isEmpty()) throw w009(PLUGIN_USAGE);
        String sub = rest.get(0);

        if (sub.equals("--help") || sub.equals("-h")) {
          System.out.println(PLUGIN_USAGE);
          return;
        }
        List<String> args = rest.subList(1, rest.size());
        switch (sub) {
          case "install" -> pluginInstall(root, args);
          case "upgrade" -> pluginUpgrade(root, args);
          case "list" -> pluginList(lock);
          case "remove" -> pluginRemove(args);
          default -> {
            ResolvedPlugin p = resolvePlugin(sub, lock);

            System.err.println("flixw: running plugin " + sub + " " + p.version()
                    + " (" + p.sha256().substring(0, 16) + "...)");
            System.err.println("       this is 3rd-party code, not audited by flixw");
            Jvm resolvedJvm = jvm != null ? jvm : selectJava(null);
            Map<String, String> env = pluginEnv(root, lock, resolvedJvm, jar, sub, p, args);
            runArtifact(p.artifact(), resolvedJvm.exe(), jar, args, env);
          }
        }
      }

      case "task" -> {
        Map<String, String> tasks = readTasks(root);

        if (rest.isEmpty() || rest.get(0).equals("--help") || rest.get(0).equals("-h")) {
          if (tasks.isEmpty()) System.out.println("(no tasks in " + tasksPath(root) + ")");
          else tasks.keySet().forEach(System.out::println);
          return;
        }
        String name = rest.get(0);
        String cmd = tasks.get(name);
        if (cmd == null)
          throw w009("no task " + q(name) + " in " + tasksPath(root)
              + (tasks.isEmpty() ? "" : "\n       known tasks: "
               + String.join(", ", tasks.keySet())));
        runTask(cmd, rest.subList(1, rest.size()));
      }

      case "examples" -> {

        if (!rest.isEmpty() && (rest.get(0).equals("--help") || rest.get(0).equals("-h"))) {
          assetHelp(EXAMPLES_ASSET, "--help"); return;
        }

        if (!rest.isEmpty() && rest.get(0).equals("local")) {
          dispatchLocal(root, jar, jvm, true, rest.subList(1, rest.size()));
          return;
        }

        if (jar == null || jvm == null)
          throw w009("examples needs a pinned, reachable compiler"
              + "\n       run: ./flixw pin <version>");
        Path asset = ensureAsset(EXAMPLES_ASSET);

        List<String> opts = jvmOpts();

        String helpText = verbId == null ? "" : storedHelp(verbId);

        boolean upstream = isUpstream(lock, env("FLIX_JAR") != null);
        List<String> a = new ArrayList<>(List.of(root.toString(), jvm.exe().toString(),
                            jar.toString(), String.valueOf(opts.size())));
        a.addAll(opts);
        a.add(helpText == null ? "" : helpText);
        a.add(String.valueOf(upstream));
        a.addAll(rest.isEmpty() ? List.of("list") : rest);
        System.exit(runAsset(asset, ensureAsset(PICOCLI_ASSET), a));
      }

      case "local" -> dispatchLocal(root, jar, jvm, false, rest);
      default -> throw w009("no wrapper implementation for " + q(verb));
    }
  }

  static final Set<String> LOCAL_BOOKKEEPING_VERBS = Set.of("add", "list", "remove", "status");

  static void dispatchLocal(Path root, Path jar, Jvm jvm, boolean forExample, List<String> rest) {
    if (!forExample && localHelpArgs(rest)) return;

    boolean help = !rest.isEmpty() && (rest.get(0).equals("--help") || rest.get(0).equals("-h"))
          || forExample && rest.size() > 1
           && (rest.get(1).equals("--help") || rest.get(1).equals("-h"));
    if (help) {
      assetHelp(LOCAL_ASSET, forExample ? "--examples-help" : "--help"); return;
    }
    String mode;
    List<String> verbAndArgs;
    if (forExample) {
      if (rest.size() < 2)
        throw w009("examples local needs a verb and an example name"
            + "\n       run: ./flixw examples local --help");

      if (rest.get(1).equals("--"))
        throw w009("examples local: <name> is required before '--'"
            + "\n       run: ./flixw examples local --help");

      if (rest.get(0).startsWith("-") || rest.get(1).startsWith("-"))
        throw w009("examples local: expected '<verb> <name>', not a flag in either position"
            + "\n       run: ./flixw examples local --help");
      mode = "example:" + rest.get(1);
      verbAndArgs = new ArrayList<>();
      verbAndArgs.add(rest.get(0));
      verbAndArgs.addAll(rest.subList(2, rest.size()));
    } else if (rest.isEmpty()) {

      mode = "standalone";
      verbAndArgs = List.of("list");
    } else {
      mode = "standalone";
      verbAndArgs = rest;
    }
    boolean bookkeeping = mode.equals("standalone") && !verbAndArgs.isEmpty()
             && LOCAL_BOOKKEEPING_VERBS.contains(verbAndArgs.get(0));
    if (!bookkeeping && (jar == null || jvm == null))
      throw w009((forExample ? "examples local" : "local") + " needs a pinned, reachable compiler"
          + "\n       run: ./flixw pin <version>");
    Path asset = ensureAsset(LOCAL_ASSET);
    List<String> opts = jvmOpts();
    List<String> a = new ArrayList<>(List.of(root.toString(),
        jvm == null ? "" : jvm.exe().toString(),
        jar == null ? "" : jar.toString(), String.valueOf(opts.size())));
    a.addAll(opts);
    a.add(mode);
    a.addAll(verbAndArgs);
    System.exit(runAsset(asset, ensureAsset(PICOCLI_ASSET), a));
  }

  static Map<String, String> readLocalOverrides(Path root) {
    Map<String, String> out = new LinkedHashMap<>();
    Path f = root.resolve(WRAPPER_DIR).resolve("local").resolve("packages.toml");
    if (!Files.isRegularFile(f)) return out;
    Pattern header = Pattern.compile("^\\[overrides\\.\"([^\"]+)\"\\]$");
    try {
      for (String raw : Files.readAllLines(f, StandardCharsets.UTF_8)) {
        Matcher h = header.matcher(raw.strip());
        if (h.matches()) out.put(h.group(1), "");
      }
    } catch (IOException ignored) { return new LinkedHashMap<>(); }
    return out;
  }

  static final Pattern GH_ASSET = Pattern.compile(
    "(https://github\\.com/[^/]+/[^/]+)/releases/download/([^/]+)/(.+)");

  static String newerAsset(String source, String have) {
    if (source == null) return null;
    Matcher m = GH_ASSET.matcher(source);
    if (!m.matches()) return null;
    String tag = latestTag(m.group(1));
    if (tag == null || canonical(strip(tag)).equals(canonical(have))) return null;
    return m.group(1) + "/releases/download/" + tag + "/" + m.group(3);
  }

  static String latestTag(String repo) {
    HttpRequest req = HttpRequest.newBuilder(URI.create(repo + "/releases/latest"))
        .method("HEAD", HttpRequest.BodyPublishers.noBody())
        .timeout(Duration.ofSeconds(60))
        .header("User-Agent", "flixw/" + WRAPPER_VERSION).build();
    try {
      HttpResponse<Void> res = httpClient().send(req, HttpResponse.BodyHandlers.discarding());
      String u = res.uri().toString();
      return res.statusCode() == 200 && u.contains("/releases/tag/")
         ? u.substring(u.lastIndexOf('/') + 1) : null;
    } catch (IOException e) {
      return null;
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return null;
    }
  }

  static String strip(String tag) { return tag.startsWith("v") ? tag.substring(1) : tag; }

  static void pluginUpgrade(Path root, List<String> args) {

    Lock lock = root == null ? null : lockIfAny();
    Map<String, PluginDep> want = new LinkedHashMap<>();
    if (lock != null) want.putAll(lock.plugins());
    for (Map.Entry<String, PluginDep> e : installedPlugins().entrySet())
      want.putIfAbsent(e.getKey(), e.getValue());
    if (want.isEmpty()) { System.out.println("(no plugins installed)"); return; }
    String only = args.isEmpty() ? null : args.get(0);
    if (only != null && !want.containsKey(only))
      throw w009("plugin " + q(only) + " is neither declared nor installed");
    boolean moved = false;
    for (Map.Entry<String, PluginDep> e : want.entrySet()) {
      if (only != null && !only.equals(e.getKey())) continue;
      String url = newerAsset(e.getValue().source(), e.getValue().version());
      if (url == null) {
        System.err.println("flixw: " + e.getKey() + " " + e.getValue().version()
                + (e.getValue().source() == null
                  || GH_ASSET.matcher(e.getValue().source()).matches()
                  ? " is the newest release"
                  : " is not on github; upgrade it with ./flixw plugin install"));
        continue;
      }
      Matcher m = GH_ASSET.matcher(url);
      String to = m.matches() ? strip(m.group(2)) : null;
      pluginInstall(root, List.of(e.getKey(), to, url));
      moved = true;
    }
    if (!moved) return;
    System.err.println("       upgraded without a digest you supplied; check what changed"
            + " and re-record it with ./flixw plugin install ... --sha256 <digest>");
  }

  static final String PLUGIN_USAGE =
     "usage: ./flixw plugin install <name> <version> <url> [--sha256 <digest>]"
    + "\n          ./flixw plugin upgrade [<name>]"
    + "\n          ./flixw plugin list"
    + "\n          ./flixw plugin remove <name>"
    + "\n          ./flixw plugin <name> [args...]";

  static Path pluginsDir() { return cacheHome().resolve("plugins"); }

  static Path pluginCacheDir(String name) {
    if (!validPluginName(name)) throw w009("invalid plugin name " + q(name));
    return cacheHome().resolve("plugin-cache").resolve(name);
  }

  static Path pluginDir(String name, String version, String sha256) {
    return pluginsDir().resolve(name).resolve(version + "-" + sha256);
  }

  static void pluginInstall(Path root, List<String> args) {
    if (args.size() < 3) throw w009(PLUGIN_USAGE);
    String name = args.get(0), version = args.get(1), url = args.get(2);
    if (!validPluginName(name))
      throw w009("plugin name " + q(name) + " must be lowercase letters, digits and"
          + " hyphens, starting with a letter");
    if (!version.matches(SEMVERISH.pattern()))
      throw w009("plugin version " + q(version) + " must look like x.y.z"
          + " (optionally with a prerelease/build suffix)");
    String wantSha = null;
    for (int i = 3; i < args.size(); i++) {
      if ("--sha256".equals(args.get(i)) && i + 1 < args.size()) wantSha = args.get(++i);
      else throw w009("plugin install: unknown option " + q(args.get(i))
             + "\n       " + PLUGIN_USAGE);
    }
    String format = url.endsWith(".jar") ? "jar" : url.endsWith(".java") ? "java"
           : url.endsWith(".flix") ? "flix" : null;
    if (format == null)
      throw w009("plugin install: url must end in .jar, .java or .flix: " + q(url));
    if (!url.startsWith("https://") && !url.startsWith("file://"))
      throw w009("plugin install: refusing " + q(url) + " (must be https:// or file://)");

    Path stagingDir = pluginsDir();
    Path tmp;
    try {
      Files.createDirectories(stagingDir);
      tmp = Files.createTempFile(stagingDir, ".plugin-", ".part");
    } catch (IOException e) { throw w009("cannot prepare " + stagingDir + ": " + why(e)); }
    try {
      if (url.startsWith("file://"))
        Files.copy(Paths.get(URI.create(url)), tmp, StandardCopyOption.REPLACE_EXISTING);
      else download(url, tmp);
      String got = sha256(tmp);
      if (wantSha != null && !got.equals(wantSha))
        throw w006("digest mismatch for " + q(url) + "\n       expected " + wantSha
            + "\n       actual   " + got);

      String desc = pluginAttribute(tmp, "Flixw-Plugin-Description", 120, format);
      String verb = pluginAttribute(tmp, "Flixw-Plugin-Command", 32, format);
      if (!verb.isEmpty()) verb = acceptPluginCommand(name, verb, root);

      Path dest = pluginDir(name, version, got);
      Files.createDirectories(dest);
      Path artifact = dest.resolve("plugin." + format);
      try { Files.move(tmp, artifact, StandardCopyOption.ATOMIC_MOVE); }
      catch (IOException e) { if (!Files.isRegularFile(artifact)) throw e; }

      if (!verb.isEmpty())
        try { writeAtomic(dest.resolve("command"), verb + "\n"); }
        catch (RuntimeException ignored) { }

      try { writeAtomic(dest.resolve("source"), url + "\n"); }
      catch (RuntimeException ignored) { }
      System.err.println("flixw: installed plugin " + name + " " + version
              + " (" + got.substring(0, 16) + "...)");

      System.err.println("       this is 3rd-party code, not audited by flixw");
      recordPluginInLock(root, name, version, got, url, desc, verb);
    } catch (IOException e) {
      throw w009("plugin install failed: " + why(e));
    } finally {
      try { Files.deleteIfExists(tmp); } catch (IOException ignored) { }
    }
  }

  static Map<String, PluginDep> installedPlugins() {
    Map<String, PluginDep> out = new LinkedHashMap<>();
    for (Path nameDir : dirsIn(pluginsDir())) {
      Path best = null;
      for (Path v : dirsIn(nameDir))
        if (best == null || olderOrSame(pluginVersionOf(best), pluginVersionOf(v))) best = v;
      if (best == null) continue;
      String src = null;
      try { src = Files.readString(best.resolve("source"), StandardCharsets.UTF_8).trim(); }
      catch (IOException ignored) { }
      String n = best.getFileName().toString();
      out.put(nameDir.getFileName().toString(),
          new PluginDep(pluginVersionOf(best), n.substring(n.length() - 64),
                 src, "", ""));
    }
    return out;
  }

  static String commandOwner(Lock lock, String verb) {
    if (lock != null)
      for (Map.Entry<String, PluginDep> e : lock.plugins().entrySet())
        if (verb.equals(e.getValue().command())) return e.getKey();
    return installedCommandOwner(verb);
  }

  static String installedCommandOwner(String verb) {
    String found = null;
    for (Path nameDir : dirsIn(pluginsDir()))
      for (Path v : dirsIn(nameDir)) {
        Path f = v.resolve("command");

        if (!Files.isRegularFile(f)) backfillCommand(v, f);
        if (!Files.isRegularFile(f)) continue;
        try {
          if (!verb.equals(Files.readString(f, StandardCharsets.UTF_8).trim())) continue;
        } catch (IOException e) { continue; }
        String name = nameDir.getFileName().toString();
        if (found != null && !found.equals(name))
          throw w009("both " + found + " and " + name + " claim " + q(verb)
              + "\n       run one by name: ./flixw plugin <name>");
        found = name;
      }
    return found;
  }

  static void backfillCommand(Path versionDir, Path into) {
    try {
      Path artifact = findPluginArtifact(versionDir);
      String ext = artifact.getFileName().toString();
      String verb = pluginAttribute(artifact, "Flixw-Plugin-Command", 32,
                     ext.substring(ext.lastIndexOf('.') + 1));
      writeAtomic(into, verb.matches(PLUGIN_NAME_PATTERN) ? verb + "\n" : "");
    } catch (IOException | RuntimeException ignored) { }
  }

  static List<Path> dirsIn(Path dir) {
    try (var s = Files.isDirectory(dir) ? Files.list(dir) : null) {
      return s == null ? List.of() : s.filter(Files::isDirectory).sorted().toList();
    } catch (IOException e) { return List.of(); }
  }

  static void runDeclaredPlugin(String name, String verb, List<String> args,
                 Path root, Lock lock, Path jar, Jvm jvm) {
    ResolvedPlugin p = resolvePlugin(name, lock);
    System.err.println("flixw: " + q(verb) + " is plugin " + name + " " + p.version()
            + " (" + p.sha256().substring(0, 16) + "...)");
    System.err.println("       this is 3rd-party code, not audited by flixw");
    Jvm resolved = jvm != null ? jvm : selectJava(null);
    runArtifact(p.artifact(), resolved.exe(), jar,
          args, pluginEnv(root, lock, resolved, jar, name, p, args));
  }

  static String acceptPluginCommand(String name, String verb, Path root) {
    Lock lock = null;
    if (root != null && Files.isRegularFile(lockPath(root)))
      try { lock = readLock(lockPath(root)); } catch (Fail ignored) { }
    if (!verb.matches(PLUGIN_NAME_PATTERN))
      throw w009("plugin " + name + " declares an unusable command " + q(verb)
          + "\n       a command is " + PLUGIN_NAME_PATTERN);
    if (WRAPPER_VERBS.contains(verb) || "wrapper".equals(verb) || "completion".equals(verb))
      throw w009("plugin " + name + " declares " + q(verb) + ", which the wrapper owns"
          + "\n       run it as: ./flixw plugin " + name);
    if (lock != null)
      for (Map.Entry<String, PluginDep> e : lock.plugins().entrySet())
        if (!e.getKey().equals(name) && verb.equals(e.getValue().command()))
          throw w009("plugin " + name + " declares " + q(verb) + ", already claimed by "
              + e.getKey() + "\n       run it as: ./flixw plugin " + name);
    return verb;
  }

  static String pluginAttribute(Path artifact, String attr, int max, String format) {
    if (!"jar".equals(format)) return "";
    try (java.util.jar.JarFile jf = new java.util.jar.JarFile(artifact.toFile(), false)) {
      java.util.jar.Manifest mf = jf.getManifest();
      return mf == null ? "" : sanitize(mf.getMainAttributes().getValue(attr), max);
    } catch (IOException | RuntimeException e) { return ""; }
  }

  static String sanitize(String s, int max) {
    if (s == null) return "";
    StringBuilder b = new StringBuilder();
    for (int i = 0; i < s.length() && b.length() < max; i++) {
      char c = s.charAt(i);
      b.append(Character.isISOControl(c) ? ' ' : c);
    }
    return b.toString().replaceAll("\\s+", " ").trim();
  }

  static void recordPluginInLock(Path root, String name, String version, String sha256,
                 String url, String description, String command) {
    if (root == null) return;
    Path lf = lockPath(root);
    if (!Files.isRegularFile(lf)) return;
    Lock have;
    try { have = readLock(lf); }
    catch (Fail ignored) { return; }
    Map<String, PluginDep> plugins = new LinkedHashMap<>(have.plugins());
    plugins.put(name, new PluginDep(version, sha256, url, description, command));
    String rewritten = lockText(WRAPPER_VERSION, have.repo() == null ? UPSTREAM_REPO : have.repo(),
      have.version(), have.url(), have.sha256(), have.reportedVersion(), have.java(), plugins);
    try { writeAtomic(lf, rewritten); System.err.println("       recorded in " + lf); }
    catch (IOException e) { tr("cannot record plugin in " + lf + ": " + e.getMessage()); }
  }

  static Path rootIfAny() {
    try { return findRoot(wrapperAnchor()); } catch (Fail e) { return null; }
  }

  static Lock lockIfAny() {
    try {
      Path root = findRoot(wrapperAnchor());
      return root == null || !Files.isRegularFile(lockPath(root)) ? null
                                   : readLock(lockPath(root));
    } catch (Fail e) {
      return null;
    }
  }

  static void pluginList(Lock lock) {
    Map<String, String> want = new LinkedHashMap<>();
    if (lock != null) lock.plugins().forEach((n, d) ->
      want.put(n, d.version() + "-" + d.sha256()));
    Path dir = pluginsDir();
    List<Path> names = List.of();
    try (var s = Files.isDirectory(dir) ? Files.list(dir) : null) {
      if (s != null) names = s.filter(Files::isDirectory).sorted().toList();
    } catch (IOException ignored) { }
    if (names.isEmpty()) { System.out.println("(no plugins installed)"); return; }
    for (Path nameDir : names) {
      List<Path> versions = List.of();
      try (var s = Files.list(nameDir)) { versions = s.filter(Files::isDirectory).sorted().toList(); }
      catch (IOException ignored) { }

      for (Path v : versions)
        System.out.println(nameDir.getFileName() + "  " + v.getFileName()
                + (v.getFileName().toString().equals(want.get(nameDir.getFileName()
                  .toString())) ? "  <= this project" : ""));
    }
  }

  static void pluginRemove(List<String> args) {
    if (args.isEmpty()) throw w009(PLUGIN_USAGE);
    String name = args.get(0);

    if (!validPluginName(name))
      throw w009("plugin name " + q(name) + " must be lowercase letters, digits and"
          + " hyphens, starting with a letter");
    Path dir = pluginsDir().resolve(name);
    if (!Files.isDirectory(dir)) throw w009("plugin " + q(name) + " is not installed");
    deleteTree(dir);

    Path data = pluginCacheDir(name);
    if (Files.isDirectory(data)) deleteTree(data);
    System.err.println("flixw: removed plugin " + name + " -- all versions, machine-wide");
  }

  record ResolvedPlugin(String version, String sha256, Path artifact) {}

  static String pluginVersionOf(Path dir) {
    String n = dir.getFileName().toString();
    return n.length() > 65 ? n.substring(0, n.length() - 65) : n;
  }

  static ResolvedPlugin resolvePlugin(String name, Lock lock) {
    if (!validPluginName(name))
      throw w009("plugin name " + q(name) + " must be lowercase letters, digits and"
          + " hyphens, starting with a letter");
    Path base = pluginsDir().resolve(name);
    PluginDep want = lock == null ? null : lock.plugins().get(name);
    Path dir;
    if (want != null) {
      dir = base.resolve(want.version() + "-" + want.sha256());
      if (!Files.isDirectory(dir))
        throw w009("plugin " + q(name) + " " + want.version() + " ("
            + want.sha256().substring(0, 12) + "...) is expected by lock.toml but"
            + " not installed\n       run: ./flixw plugin install " + name + " "
            + want.version() + " <url> --sha256 " + want.sha256());
    } else {
      if (!Files.isDirectory(base))
        throw w009("plugin " + q(name) + " is not installed"
            + "\n       run: ./flixw plugin install " + name + " <version> <url>");
      List<Path> versions;
      try (var s = Files.list(base)) { versions = s.filter(Files::isDirectory).sorted().toList(); }
      catch (IOException e) { throw w009("cannot read " + base + ": " + why(e)); }
      if (versions.isEmpty())
        throw w009("plugin " + q(name) + " is not installed"
            + "\n       run: ./flixw plugin install " + name + " <version> <url>");

      dir = versions.get(0);
      for (Path v : versions)
        if (olderOrSame(pluginVersionOf(dir), pluginVersionOf(v))) dir = v;
      if (versions.size() > 1)
        tr("plugin " + name + ": " + versions.size() + " installed, running "
        + pluginVersionOf(dir) + "; pin one with ./flixw plugin install");
    }
    Path artifact = findPluginArtifact(dir);

    String dirName = dir.getFileName().toString();
    String sha256 = dirName.substring(dirName.length() - 64);
    String version = dirName.substring(0, dirName.length() - 65);
    String got = sha256(artifact);
    if (!got.equals(sha256))
      throw w006("plugin " + q(name) + " " + version + " no longer matches the digest"
          + " it was installed with\n       expected " + sha256
          + "\n       actual   " + got
          + "\n       run: ./flixw plugin remove " + name
          + "   then reinstall");
    markUsed("plugin/" + name + "/" + dirName);
    return new ResolvedPlugin(version, sha256, artifact);
  }

  static Path findPluginArtifact(Path dir) {
    for (String ext : List.of(".jar", ".java", ".flix")) {
      Path p = dir.resolve("plugin" + ext);
      if (Files.isRegularFile(p)) return p;
    }
    throw w009("plugin cache at " + dir + " has no plugin.jar, plugin.java or plugin.flix");
  }

  static String cmdQuote(String arg) {
    if (!arg.isEmpty() && arg.chars().noneMatch(
        c -> c == ' ' || c == '\t' || c == '"' || c == '&' || c == '|'
         || c == '<' || c == '>' || c == '^' || c == '%'))
      return arg;
    return '"' + arg.replace("\"", "\"\"") + '"';
  }

  static void runTask(String command, List<String> extraArgs) {
    List<String> cmd = new ArrayList<>();
    if (isWindows()) {
      cmd.add("cmd"); cmd.add("/c"); cmd.add(command);

      for (String a : extraArgs) cmd.add(cmdQuote(a));
    } else {
      cmd.add("sh"); cmd.add("-c"); cmd.add(command + " \"$@\""); cmd.add("sh");
      cmd.addAll(extraArgs);
    }
    tr("exec " + String.join(" ", cmd));
    try {
      System.exit(awaitWithReaper(new ProcessBuilder(cmd).inheritIO().start()));
    } catch (IOException e) {
      throw w005("cannot run task: " + e.getMessage());
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      System.exit(130);
    }
  }

  static String askedVersion(Lock lock) {
    return lock == null ? null : lock.reportedVersion();
  }

  static void report(Path root, Lock lock, Path jar, Jvm jvm, List<String> cv, String reported) {
    System.out.println("flixw            " + WRAPPER_VERSION);
    System.out.println("project root     " + root);
    System.out.println("compiler         " + (lock == null ? "-" : lock.version()));
    System.out.println("source           " + (lock == null ? "-"
      : (lock.repo() == null ? UPSTREAM_REPO : lock.repo())
       + (lock.repo() != null && !lock.repo().equals(UPSTREAM_REPO)
        ? "  (a fork; not stock-compatibility evidence)" : "")));

    if (reported != null && lock != null && !reported.equals(lock.version()))
      System.out.println("reported         " + reported + "  ("
        + (canonical(reported).equals(canonical(lock.version()))
         ? "the compiler does not carry the build metadata the lock pins"
         : "MISMATCH -- the lock pins " + lock.version()) + ")");
    System.out.println("digest           " + (lock == null ? "-" : lock.sha256()));
    System.out.println("jar              " + (jar == null ? "-" : jar));
    System.out.println("java             " + (jvm == null ? "-" : jvm.exe() + "  (" + jvm.feature()
                         + ", via " + jvm.how() + ")"));
    System.out.println("java pin         " + (lock == null || lock.java() == null
      ? "-  (any tested JDK)" : lock.java()));
    System.out.println("cache            " + cacheHome());
    System.out.println("dist url         " + (lock == null ? "-" : redact(rewriteBase(lock.url()))));
    if (env("FLIX_DIST_URL") != null) System.out.println("mirror           FLIX_DIST_URL is set");
    for (String p : new String[] { "HTTPS_PROXY", "https_proxy", "NO_PROXY" })
      if (env(p) != null) System.out.println("proxy            " + p + "=" + redact(env(p)));
    for (String p : new String[] { "JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS" })
      if (env(p) != null) System.out.println("note             " + p + "=" + redactOpts(env(p))
                        + "  (affects the JVM and stderr)");
    if (env("FLIX_JAR") != null) {
      System.out.println("override         FLIX_JAR=" + env("FLIX_JAR")
              + "  (unverified; not stock-compatibility evidence)");

      if (jar != null && Files.isRegularFile(jar)) {
        String got = sha256(jar);
        System.out.println("override digest  " + got + (lock == null ? ""
          : got.equals(lock.sha256()) ? "  (the jar the lock pins)"
          : "  (NOT the jar the lock pins)"));
      }
    }
    System.out.println("compiler verbs   " + (cv == null ? "(not captured)" : String.join(" ", cv)));
    List<String> fallback = new ArrayList<>(WRAPPER_VERBS);
    if (cv != null) fallback.removeAll(cv);
    System.out.println("wrapper verbs    " + String.join(" ", fallback));
    System.out.println("pass-through     ./flixw -- <args>");
  }

  static void listCache(Lock lock, Jvm jvm) {
    Path ctx = null;
    try {
      ctx = Files.createTempFile("flixw-inspect-", ".txt");
      Files.writeString(ctx, inspectContext(lock, jvm), StandardCharsets.UTF_8);
      Path asset = ensureAsset(INSPECT_ASSET);
      runAsset(asset, null, List.of(ctx.toString()));
    } catch (IOException | RuntimeException e) {
      System.out.println();
      System.out.println("the cache inventory needs " + INSPECT_ASSET + ", which could not"
              + " be fetched:");
      System.out.println("  " + (e.getMessage() == null ? e.toString() : e.getMessage()));
      System.out.println("  everything above came from this wrapper and is unaffected.");
    } finally {
      if (ctx != null) { try { Files.deleteIfExists(ctx); } catch (IOException ignored) { } }
    }
  }

  static void purgeCache(int days, boolean yes) {
    Path ctx = null;
    try {
      ctx = Files.createTempFile("flixw-purge-", ".txt");

      Files.writeString(ctx, inspectContext(null, null), StandardCharsets.UTF_8);
      Path asset = ensureAsset(INSPECT_ASSET);
      int rc = runAsset(asset, null, List.of(ctx.toString(), "--purge",
        String.valueOf(days), yes ? "--yes" : "--ask"));
      if (rc != 0) throw w009("cache purge failed (exit " + rc + ")");
    } catch (IOException e) {
      throw w005("cannot purge the cache: " + why(e));
    } finally {
      if (ctx != null) { try { Files.deleteIfExists(ctx); } catch (IOException ignored) { } }
    }
  }

  static String inspectContext(Lock lock, Jvm jvm) {
    StringBuilder b = new StringBuilder();
    b.append("cacheRoot=").append(cacheHome()).append('\n');
    b.append("wrapperVersion=").append(canonical(WRAPPER_VERSION)).append('\n');
    b.append("upstreamRepo=").append(UPSTREAM_REPO).append('\n');
    b.append("lockSha256=").append(lock == null ? "" : lock.sha256()).append('\n');
    b.append('\n').append("lockPlugins:").append('\n');
    if (lock != null)
      for (Map.Entry<String, PluginDep> e : lock.plugins().entrySet())
        b.append(e.getKey()).append('\t')
        .append(e.getValue().version()).append('-').append(e.getValue().sha256()).append('\n');

    b.append('\n').append("cachedJdks:").append('\n');
    Path installed = installedJdk();
    for (Path dir : cachedJdkDirs()) {
      Path exe = findJavaUnder(dir);
      if (exe == null) continue;
      String v = probeVersion(exe);
      b.append(v == null ? "(unknown)" : v).append('\t')
      .append(dir.getFileName()).append('\t')
      .append(exe.equals(installed) ? "default" : "").append('\n');
    }

    b.append('\n').append("systemJdks:").append('\n');
    for (Path exe : knownInstalls()) {
      String v = probeVersion(exe);
      int f = probe(exe);
      b.append(v == null ? "(unknown)" : v).append('\t').append(exe).append('\t')
      .append(jvm != null && exe.equals(jvm.exe()) ? "  <= selected"
         : f >= 0 && f < MIN_JAVA ? "  (below Java " + MIN_JAVA + ")" : "").append('\n');
    }
    return b.toString();
  }

  static List<Path> cachedJdkDirs() {
    try (var s = Files.isDirectory(cacheHome().resolve("jdks"))
          ? Files.list(cacheHome().resolve("jdks")) : null) {
      return s == null ? List.of() : s.filter(Files::isDirectory).sorted().toList();
    } catch (IOException e) { return List.of(); }
  }

  static void printAligned(List<String[]> rows) {
    if (rows.isEmpty()) { System.out.println("  (none)"); return; }
    int w0 = rows.stream().mapToInt(r -> r[0].length()).max().orElse(0);
    int w1 = rows.stream().mapToInt(r -> r[1].length()).max().orElse(0);
    for (String[] r : rows)
      System.out.println("  " + pad(r[0], w0) + "  " + pad(r[1], w1) + r[2]);
  }

  static String pad(String s, int width) {
    return width <= s.length() ? s : s + " ".repeat(width - s.length());
  }

  static String humanSize(long bytes) {
    if (bytes < 0) return "?";
    double mb = bytes / (1024.0 * 1024.0);
    return String.format(Locale.ROOT, "%.1f MB", mb);
  }

  static int checkCanonical(Path file, String wantDigest, String label) {
    if (!Files.isRegularFile(file)) { System.out.println("FAIL  missing " + label); return 1; }
    try {
      if (sha256(file).equals(wantDigest)) {
        System.out.println("ok    " + label + " matches flixw " + WRAPPER_VERSION);
        return 0;
      }
      System.out.println("FAIL  " + label + " differs from flixw " + WRAPPER_VERSION
              + " (./flixw doctor --fix)");
    } catch (Fail e) {
      System.out.println("FAIL  unreadable " + label + ": " + e.getMessage());
    }
    return 1;
  }

  static String canonicalAttrs(String shipped) {
    return shipped.equals("flixw.cmd") ? "text eol=crlf" : "text eol=lf";
  }

  static boolean changesEndings(String attrs, String shipped, Map<String, String> macros) {
    String pinned = " " + canonicalAttrs(shipped) + " ";
    for (String token : attrs.split("\\s+")) {
      String name = token.replaceFirst("^[-!]", "").replaceFirst("=.*", "");
      String macro = macros.get(name);
      if (macro != null) {
        if (changesEndings(macro, shipped, Map.of())) return true;
        continue;
      }
      if (!name.equals("text") && !name.equals("eol")) continue;

      if (token.equals("text=auto") && pinned.contains(" text ")) continue;
      if (!pinned.contains(" " + token + " ")) return true;
    }
    return false;
  }

  static Map<String, String> attrMacros(String text) {
    Map<String, String> macros = new LinkedHashMap<>();
    macros.put("binary", "-diff -merge -text");
    for (String line : text.split("\r?\n")) {
      String t = line.trim();
      if (!t.startsWith("[attr]")) continue;
      String[] parts = t.substring("[attr]".length()).split("\\s+", 2);
      if (parts.length == 2) macros.putIfAbsent(parts[0], parts[1]);
    }
    return macros;
  }

  static final List<String> SHIPPED =
    List.of("flixw", "flixw.cmd", WRAPPER_DIR + "/flixw.java", WRAPPER_DIR + "/lock.toml",
        WRAPPER_DIR + "/.gitignore", WRAPPER_DIR + "/.sccignore");

  static boolean patternMatches(String pattern, String path) {
    String p = pattern.startsWith("/") ? pattern.substring(1) : pattern;
    if (p.equals("*") || p.equals("**") || p.equals(path)) return true;
    if (p.startsWith("*.") && path.endsWith(p.substring(1))) return true;

    return !p.contains("/") && (path.equals(p) || path.endsWith("/" + p));
  }

  static int checkGitattributes(Path ga) {
    if (!Files.isRegularFile(ga)) {
      System.out.println("warn  no .gitattributes; line endings are unpinned");
      return 0;
    }
    String text;
    try { text = Files.readString(ga, StandardCharsets.UTF_8); }
    catch (IOException e) { System.out.println("FAIL  unreadable .gitattributes"); return 1; }

    String begin = "# >>> flixw >>>", end = "# <<< flixw <<<";
    int opens = count(text, begin), closes = count(text, end);
    if (opens == 0 && closes == 0) {
      System.out.println("warn  .gitattributes has no flixw block (./flixw doctor --fix)");
      return 0;
    }
    int bad = 0;

    if (opens != 1 || closes != 1) {
      System.out.println("FAIL  .gitattributes has " + opens + " flixw start and "
              + closes + " end markers; expected one of each"
              + " (./flixw doctor --fix)");
      bad++;
    }
    int after = text.lastIndexOf(end);
    if (after < 0) return bad;
    Map<String, String> macros = attrMacros(text);
    for (String line : text.substring(after).split("\r?\n")) {
      String t = line.trim();
      if (t.isEmpty() || t.startsWith("#")) continue;
      String pattern = t.split("\\s+")[0];
      String attrs = t.substring(pattern.length()).trim();
      for (String f : SHIPPED) {
        if (patternMatches(pattern, f) && changesEndings(attrs, f, macros)) {
          System.out.println("FAIL  .gitattributes rule " + q(t)
                  + " comes after the flixw block and changes " + f);
          bad++;
          break;
        }
      }
    }
    if (bad == 0) System.out.println("ok    .gitattributes block is not overridden");
    return bad;
  }

  static int count(String haystack, String needle) {
    int n = 0, at = 0;
    while ((at = haystack.indexOf(needle, at)) >= 0) { n++; at += needle.length(); }
    return n;
  }

  static Integer git(Path root, String... args) {
    List<String> cmd = new ArrayList<>(List.of("git"));
    cmd.addAll(Arrays.asList(args));
    Process p = null;
    try {
      p = new ProcessBuilder(cmd).directory(root.toFile())
          .redirectOutput(ProcessBuilder.Redirect.DISCARD)
          .redirectError(ProcessBuilder.Redirect.DISCARD).start();
      return p.waitFor(30, TimeUnit.SECONDS) ? p.exitValue() : null;
    } catch (IOException | InterruptedException e) {
      if (e instanceof InterruptedException) Thread.currentThread().interrupt();
      return null;
    } finally {

      if (p != null && p.isAlive()) p.destroyForcibly();
    }
  }

  static int check(Path root, Lock lock, Path jar, Jvm jvm) {
    int bad = 0;

    bad += checkCanonical(root.resolve("flixw"), SHIM_SHA256, "./flixw");
    bad += checkCanonical(root.resolve("flixw.cmd"), CMD_SHA256, "./flixw.cmd");
    if (!isWindows() && Files.isRegularFile(root.resolve("flixw"))
      && !Files.isExecutable(root.resolve("flixw"))) {
      System.out.println("FAIL  ./flixw is not executable (./flixw doctor --fix)"); bad++;
    }

    Path src = root.resolve(WRAPPER_DIR).resolve("flixw.java");
    if (!Files.isRegularFile(src)) {
      System.out.println("FAIL  missing " + WRAPPER_DIR + "/flixw.java"); bad++;
    } else {
      try {
        System.out.println("ok    " + WRAPPER_DIR + "/flixw.java  sha256="
                + sha256(Files.readAllBytes(src)));
      } catch (IOException e) {
        System.out.println("FAIL  unreadable " + WRAPPER_DIR + "/flixw.java"); bad++;
      }
    }

    String mv = null;
    try { mv = manifestVersion(root.resolve("flix.toml")); }
    catch (Fail f) {

      System.out.println("FAIL  " + f.getMessage().split("\n")[0]);
      bad++;
    }
    if (lock == null) { System.out.println("FAIL  no lock"); bad++; }
    else if (mv != null && !olderOrSame(triple(mv), triple(lock.version()))) {
      System.out.println("FAIL  flix.toml asks for " + mv + " or newer, lock pins "
              + lock.version()); bad++;
    } else System.out.println("ok    the lock satisfies flix.toml");

    if (lock != null) {
      try {
        String text = Files.readString(lockPath(root), StandardCharsets.UTF_8);
        if (text.startsWith("#:schema " + LOCK_SCHEMA_URL + "\n"))
          System.out.println("ok    the lock conforms to, and names, the "
                  + LOCK_SCHEMA_VERSION + " schema");
        else
          System.out.println("warn  the lock conforms to the " + LOCK_SCHEMA_VERSION
                  + " schema but does not name it; editors will not"
                  + " validate it (./flixw doctor --fix)");
      } catch (IOException e) {
        System.out.println("FAIL  unreadable " + WRAPPER_DIR + "/lock.toml"); bad++;
      }
    }

    if (lock != null && lock.java() != null) {
      String got = jvm == null ? null : probeVersion(jvm.exe());
      if (satisfiesJavaPin(lock.java(), got))
        System.out.println("ok    java " + got + " satisfies the pinned java " + lock.java());
      else {
        System.out.println("FAIL  java " + (got == null ? "unidentifiable" : got)
                + " does not satisfy the pinned java " + lock.java()
                + " (./flixw wrapper --install-jdk)"); bad++;
      }
    }

    if (lock != null && jar != null && jvm != null) {
      String rv = askedVersion(lock);
      if (rv == null)
        System.out.println("warn  the lock records no reported_version; nothing to"
                + " check it against (./flixw pin --refresh)");
      else if (canonical(rv).equals(canonical(lock.version())))
        System.out.println(rv.equals(lock.version())
          ? "ok    the compiler reports the version the lock pins"
          : "warn  the compiler reports " + rv + "; the lock pins " + lock.version()
          + " (build metadata only)");
      else {
        System.out.println("FAIL  the compiler reports " + rv + ", but the lock pins "
                + lock.version() + " (./flixw pin " + rv + ")");
        bad++;
      }
    }
    if (jar != null && Files.isRegularFile(jar)) System.out.println("ok    cached compiler digest");

    if (root != null && lock != null && jar != null && Files.isRegularFile(jar)) {
      Path editorJar = root.resolve("flix.jar");
      EditorJarPref pref = readEditorJarPref(root);
      if (pref == null || !pref.mode().equals("off")) {
        if (!Files.exists(editorJar, LinkOption.NOFOLLOW_LINKS))
          System.out.println("warn  no ./flix.jar for the VS Code Flix extension"
                  + " (./flixw pin --editor-jar=copy, or re-run ./flixw pin)");
        else if (!Files.isReadable(editorJar))
          System.out.println("warn  ./flix.jar is a broken link"
                  + " (./flixw pin --editor-jar=copy)");
        else {
          boolean managed = Files.isSymbolicLink(editorJar)
            || (pref != null && pref.mode().equals("copy"));
          String kind = Files.isSymbolicLink(editorJar) ? "link" : "managed copy";
          if (sha256(editorJar).equals(lock.sha256()))
            System.out.println("ok    ./flix.jar (" + kind + ") matches the pinned compiler");
          else if (managed)
            System.out.println("warn  ./flix.jar (" + kind + ") does not match the pinned"
                    + " compiler (./flixw pin --editor-jar=copy, or re-run"
                    + " ./flixw pin)");
          else
            System.out.println("warn  ./flix.jar exists and was not created by this"
                    + " project's flixw; it is not being kept in sync");
        }
      }
    }

    if (root != null) {
      Map<String, String> overrides = readLocalOverrides(root);
      if (!overrides.isEmpty())
        System.out.println("warn  " + overrides.size() + " local dependency override"
                + (overrides.size() == 1 ? "" : "s") + " active: "
                + String.join(", ", overrides.keySet())
                + " (./flixw local status)");
    }

    if (lock != null) {
      for (var entry : lock.plugins().entrySet()) {
        String name = entry.getKey();
        PluginDep want = entry.getValue();
        if (Files.isDirectory(pluginDir(name, want.version(), want.sha256())))
          System.out.println("ok    plugin " + name + " " + want.version() + " is installed");
        else
          System.out.println("warn  plugin " + name + " " + want.version()
                  + " is expected by lock.toml but not installed"
                  + " (./flixw plugin install " + name + " " + want.version()
                  + " <url> --sha256 " + want.sha256() + ")");
      }
    }

    for (String kind : List.of("stage0", "jdks")) {
      Path dir = cacheHome().resolve(kind);
      if (!Files.isDirectory(dir)) continue;
      try {
        var perms = Files.getPosixFilePermissions(dir);
        if (perms.contains(java.nio.file.attribute.PosixFilePermission.GROUP_WRITE)
        || perms.contains(java.nio.file.attribute.PosixFilePermission.OTHERS_WRITE)) {
          System.out.println("warn  " + dir + " is writable by others;"
                  + " the shims execute what is in it (set FLIX_CACHE_HOME)");
        } else {
          System.out.println("ok    " + kind + " cache is private to you");
        }
      } catch (IOException | UnsupportedOperationException ignored) {

      }
    }
    bad += checkGitattributes(root.resolve(".gitattributes"));

    Integer isRepo = git(root, "rev-parse", "--is-inside-work-tree");
    if (isRepo == null || isRepo != 0) {
      System.out.println("warn  not a git work tree; cannot check tracked status");
    } else {
      for (String rel : SHIPPED) {

        if (!Files.exists(root.resolve(rel))) continue;
        Integer ignored = git(root, "check-ignore", "-q", "--", rel);
        if (ignored != null && ignored == 0) {
          System.out.println("FAIL  " + rel + " is matched by a gitignore rule"); bad++;
          continue;
        }
        Integer tracked = git(root, "ls-files", "--error-unmatch", "--", rel);
        if (tracked != null && tracked != 0) {
          System.out.println("warn  " + rel + " is not tracked yet (git add " + rel + ")");
        } else System.out.println("ok    " + rel + " is tracked");
      }
    }
    return bad;
  }

  static void writeAtomic(Path file, String text) throws IOException {
    Path dir = file.getParent();
    Path tmp = Files.createTempFile(dir, "." + file.getFileName() + "-", ".part");
    try {
      Files.writeString(tmp, text, StandardCharsets.UTF_8);
      try {
        Files.move(tmp, file, StandardCopyOption.ATOMIC_MOVE);
      } catch (java.nio.file.AtomicMoveNotSupportedException e) {
        Files.move(tmp, file, StandardCopyOption.REPLACE_EXISTING);
      }
      tmp = null;
    } finally {
      if (tmp != null) { try { Files.deleteIfExists(tmp); } catch (IOException ignored) { } }
    }
  }

  static void restore(Path file, String previous) {
    try {
      if (previous == null) Files.deleteIfExists(file);
      else writeAtomic(file, previous);
    } catch (IOException ignored) { }
  }

  static Path editorJarPrefsFile(Path root) {
    return root.resolve(WRAPPER_DIR).resolve("local").resolve("editor-jar.toml");
  }

  record EditorJarPref(String mode, String sha256) {}

  static EditorJarPref readEditorJarPref(Path root) {
    Path f = editorJarPrefsFile(root);
    if (!Files.isRegularFile(f)) return null;
    String mode = null, sha = null;
    try {
      for (String line : Files.readAllLines(f, StandardCharsets.UTF_8)) {
        String t = line.strip();
        int eq = t.indexOf('=');
        if (eq < 0) continue;
        String key = t.substring(0, eq).strip();
        String val = t.substring(eq + 1).strip().replaceAll("^\"|\"$", "");
        if (key.equals("mode")) mode = val; else if (key.equals("sha256")) sha = val;
      }
    } catch (IOException e) { return null; }
    return mode == null ? null : new EditorJarPref(mode, sha);
  }

  static void writeEditorJarPref(Path root, String mode, String sha256) {
    try {
      Path f = editorJarPrefsFile(root);
      Files.createDirectories(f.getParent());
      writeAtomic(f, "mode = \"" + mode + "\"\n"
             + (sha256 == null ? "" : "sha256 = \"" + sha256 + "\"\n"));
    } catch (IOException e) {
      tr("cannot write .flixw/local/editor-jar.toml: " + e.getMessage());
    }
  }

  static boolean ownsEditorJar(Path link, EditorJarPref pref) {
    try {
      if (Files.isSymbolicLink(link)) {
        Path real = link.toRealPath();
        Path compilers = cacheHome().resolve("compilers").toRealPath();
        return real.startsWith(compilers);
      }
      return pref != null && pref.sha256() != null && pref.sha256().equals(sha256(link));
    } catch (IOException e) { return false; }
  }

  static boolean tryEditorJarLink(Path link, Path target, boolean hard) {
    try {
      Files.createDirectories(link.getParent());
      Path tmp = Files.createTempFile(link.getParent(), ".flix.jar-", ".part");
      Files.delete(tmp);
      if (hard) Files.createLink(tmp, target); else Files.createSymbolicLink(tmp, target);
      Files.move(tmp, link, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
      return true;
    } catch (IOException | UnsupportedOperationException e) { return false; }
  }

  static void ensureGitignored(Path root, String line) {
    try {
      Path gi = root.resolve(".gitignore");
      String cur = Files.isRegularFile(gi) ? Files.readString(gi, StandardCharsets.UTF_8) : "";
      if (cur.lines().anyMatch(l -> l.strip().equals(line))) return;
      String next = (cur.isEmpty() || cur.endsWith("\n") ? cur : cur + "\n") + line + "\n";
      writeAtomic(gi, next);
    } catch (IOException e) {
      tr("cannot add " + line + " to .gitignore: " + e.getMessage());
    }
  }

  static void maintainEditorJar(Path root, Path jar, String requestedMode) {
    ensureGitignored(root, "/flix.jar");
    EditorJarPref pref = readEditorJarPref(root);
    Path link = root.resolve("flix.jar");
    if ("off".equals(requestedMode)) {

      if (Files.exists(link, LinkOption.NOFOLLOW_LINKS) && ownsEditorJar(link, pref)) {
        try { Files.delete(link); } catch (IOException e) { tr("cannot remove flix.jar: " + e.getMessage()); }
      }
      writeEditorJarPref(root, "off", null);
      return;
    }
    if (requestedMode == null && pref != null && pref.mode().equals("off")) return;

    if (requestedMode != null && pref != null && pref.mode().equals("off")) {
      try { Files.deleteIfExists(editorJarPrefsFile(root)); } catch (IOException ignored) { }
      pref = null;
    }
    boolean exists = Files.exists(link, LinkOption.NOFOLLOW_LINKS);
    if (exists && !ownsEditorJar(link, pref) && !"copy".equals(requestedMode)) {
      System.err.println("flixw: note: ./flix.jar exists and was not created by this"
              + " project's flixw -- leave it, or run"
              + " ./flixw pin --editor-jar=copy to replace it");
      return;
    }

    if (tryEditorJarLink(link, jar, false)) return;
    if (tryEditorJarLink(link, jar, true)) return;

    boolean copy = "copy".equals(requestedMode) || (pref != null && pref.mode().equals("copy"));
    boolean persist = "copy".equals(requestedMode);
    if (!copy && requestedMode == null && System.console() != null) {
      System.err.print("flixw: could not link ./flix.jar for VS Code (a different volume"
              + " than the cache, or no symlink privilege). Create a managed copy"
              + " instead? [y] once  [n] skip  [a] always for this checkout: ");
      System.err.flush();
      String answer;
      try { answer = new java.io.BufferedReader(new java.io.InputStreamReader(System.in))
                .readLine(); } catch (IOException e) { answer = null; }
      answer = answer == null ? "n" : answer.strip().toLowerCase();
      if (answer.equals("a")) { copy = true; persist = true; }
      else if (answer.equals("y")) copy = true;
      else return;
    }
    if (!copy) {
      if (requestedMode == null && System.console() == null)
        tr("flix.jar could not be linked for VS Code, and this run is"
        + " non-interactive; re-run with --editor-jar=copy to make a managed copy");
      return;
    }
    try {
      Path tmp = Files.createTempFile(root, ".flix.jar-", ".part");
      Files.copy(jar, tmp, StandardCopyOption.REPLACE_EXISTING);
      Files.move(tmp, link, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
      if (persist) writeEditorJarPref(root, "copy", sha256(link));
    } catch (IOException e) {
      tr("cannot copy flix.jar for VS Code: " + e.getMessage());
    }
  }

  static void pin(Path root, Pin what) {
    if (what.refresh()) { refreshPin(root); return; }
    String repo = what.repo(), version = what.version(), java = what.java();
    boolean clearJava = what.clearJava();
    Path lockFile0 = lockPath(root);

    Lock had = null;
    if (Files.isRegularFile(lockFile0)) {
      try { had = readLock(lockFile0); } catch (Fail ignored) { }
    }

    String javaPin = clearJava ? null : (java != null ? java : had == null ? null : had.java());

    if (version == null) {
      if (had == null)
        throw w002("pin: --java or --editor-jar needs a lock that parses"
            + "\n       run: ./flixw pin <version> --java <version>");
      String lock = lockText(WRAPPER_VERSION, had.repo() == null ? UPSTREAM_REPO : had.repo(),
                 had.version(), had.url(), had.sha256(), had.reportedVersion(),
                 javaPin, had.plugins());
      try { writeAtomic(lockFile0, lock); }
      catch (IOException e) { throw w009("pin failed: " + why(e)); }

      if (java != null || clearJava)
        System.err.println(javaPin == null
          ? "flixw: unpinned java; the newest tested JDK will be used"
          : "flixw: pinned java " + javaPin);
      if (what.editorJar() != null) {

        try {
          Path jar = acquire(had);
          maintainEditorJar(root, jar, what.editorJar());
        } catch (Fail e) {
          System.err.println("flixw: note: could not reach the pinned compiler to"
                  + " update ./flix.jar: " + e.getMessage());
        }
      }
      warnMissingJava(javaPin);
      return;
    }
    Asset asset = resolveRelease(repo, version);
    String url = asset.url();
    Path wrapperDir = root.resolve(WRAPPER_DIR);
    Path tmp;
    try {
      Files.createDirectories(wrapperDir);
      tmp = Files.createTempFile(wrapperDir, ".pin-", ".part");
    }
    catch (IOException e) { throw w009("cannot write in " + wrapperDir + ": " + e.getMessage()); }
    Path lockFile = lockPath(root);
    boolean hadLock = Files.isRegularFile(lockFile);
    String oldLock = null;

    boolean snapshot = !hadLock;
    if (hadLock) {
      try { oldLock = Files.readString(lockFile, StandardCharsets.UTF_8); snapshot = true; }
      catch (IOException ignored) { }
    }
    try {
      download(rewriteBase(url), tmp);
      String digest = sha256(tmp);

      Path jar = cacheHome().resolve("compilers")
            .resolve("flix-" + canonical(version) + "-" + digest + ".jar");
      if (!Files.isRegularFile(jar)) {
        try {
          Files.createDirectories(jar.getParent());
          Files.move(tmp, jar, StandardCopyOption.ATOMIC_MOVE);
        } catch (IOException ignored) { }
      }

      String reported = captureReportedVersion(
        Files.isRegularFile(jar) ? jar : tmp, javaPin);

      String lock = lockText(WRAPPER_VERSION, repo, version, url, digest, reported, javaPin,
                 had == null ? Map.of() : had.plugins());

      writePinRecord(digest, repo, version);

      writeAtomic(lockFile, lock);
      System.err.println("flixw: pinned Flix " + version + " from " + repo
              + " (" + digest.substring(0, 16) + "...)");
      if (!repo.equals(UPSTREAM_REPO))
        System.err.println("       a fork is not stock-compatibility evidence;"
                + " see docs/LIMITATIONS.md");
      reportVersionGap("the JAR just pinned", version, reported);

      warnMissingJava(javaPin);
      String floor = null;
      try { floor = manifestVersion(root.resolve("flix.toml")); } catch (Fail ignored) { }
      if (floor != null && !olderOrSame(triple(floor), triple(version)))
        System.err.println("       note: flix.toml asks for " + floor + " or newer,"
                + " so this lock will not run until one of them moves");

      if (Files.isRegularFile(jar)) maintainEditorJar(root, jar, what.editorJar());
    } catch (IOException e) {
      if (snapshot) restore(lockFile, oldLock);
      throw w009("pin failed: " + why(e));
    } finally { try { Files.deleteIfExists(tmp); } catch (IOException ignored) {} }
  }

  static void updateWrapper(Path root) {
    runSetupAsset(List.of("update", root.toString()));

    try {
      if (refreshLock(root).changed())
        System.out.println("rewrote  " + WRAPPER_DIR + "/lock.toml");
    } catch (Fail unparseable) {
    } catch (IOException e) { throw w009("rewriting the lock failed: " + why(e)); }
  }

  static void warnMissingJava(String javaPin) {
    if (javaPin == null || javaPinAvailable(javaPin)) return;
    System.err.println("       note: no Java " + javaPin + " on this machine;"
            + " nothing here will run the compiler until there is");
    System.err.println("       run: ./flixw wrapper --install-jdk   (fetches Temurin "
            + feature(javaPin) + " into the flixw cache)");
  }

  static String tomlEscape(String s) {
    return s.replace("\\", "\\\\").replace("\"", "\\\"");
  }

  static String lockText(String wrapper, String repo, String version, String url,
             String sha256, String reportedVersion, String java,
             Map<String, PluginDep> plugins) {
    String body = """
            #:schema %s
            # Generated by flixw. Do not edit by hand; commit this file.
            wrapperVersion = "%s"

            [compiler]
            repo    = "%s"
            version = "%s"
            url     = "%s"
            sha256  = "%s"
            """.formatted(LOCK_SCHEMA_URL, wrapper, repo, version, url, sha256);

    if (reportedVersion != null)
      body += "reported_version = \"" + reportedVersion + "\"\n";

    if (java != null) body += """

            [java]
            version = "%s"
            """.formatted(java);

    for (String name : plugins.keySet().stream().sorted().toList()) {
      PluginDep p = plugins.get(name);
      body += "\n[plugins." + name + "]\n"
         + "version = \"" + p.version() + "\"\n"
         + "sha256  = \"" + p.sha256() + "\"\n"
         + (p.source() == null ? "" : "source  = \"" + p.source() + "\"\n")

         + (p.description() == null || p.description().isEmpty() ? ""
          : "description = \"" + tomlEscape(p.description()) + "\"\n")
         + (p.command() == null || p.command().isEmpty() ? ""
          : "command = \"" + p.command() + "\"\n");
    }
    return body;
  }

  record Refresh(boolean changed, String why) {}

  static Refresh refreshLock(Path root) throws IOException {
    Path lockFile = lockPath(root);
    if (!Files.isRegularFile(lockFile))
      return new Refresh(false, "there is no " + WRAPPER_DIR + "/lock.toml");
    String text = Files.readString(lockFile, StandardCharsets.UTF_8);

    Lock lock = readLock(lockFile);
    String w = lockFile.toString();
    String wroteIt = tomlLookup(text, "", "wrapperVersion", w);
    if (wroteIt != null && !olderOrSame(wroteIt, WRAPPER_VERSION))
      return new Refresh(false, "the lock was written by flixw " + wroteIt
                  + ", which is newer than this one (" + WRAPPER_VERSION + ")");
    List<String> unknown = unknownLockKeys(text, w);
    if (!unknown.isEmpty())
      return new Refresh(false, "the lock carries " + String.join(", ", unknown)
                  + ", which this flixw does not read and would drop");

    String reported = lock.reportedVersion();
    if (reported == null) {
      Path cached = compilerPath(lock);
      if (Files.isRegularFile(cached) && sha256(cached).equals(lock.sha256()))
        reported = captureReportedVersion(cached, lock.java());
    }
    String want = lockText(WRAPPER_VERSION, lock.repo() == null ? UPSTREAM_REPO : lock.repo(),
               lock.version(), lock.url(), lock.sha256(), reported, lock.java(),
               lock.plugins());
    if (want.equals(text))
      return new Refresh(false, "the lock is already what flixw " + WRAPPER_VERSION
                  + " writes");
    writeAtomic(lockFile, want);
    return new Refresh(true, null);
  }

  static void refreshPin(Path root) {
    Refresh r;
    try { r = refreshLock(root); }
    catch (IOException e) { throw w009("pin --refresh failed: " + why(e)); }
    System.err.println(r.changed()
      ? "flixw: rewrote " + WRAPPER_DIR + "/lock.toml in the shape flixw "
       + WRAPPER_VERSION + " writes; the pin is unchanged"
      : "flixw: nothing to do -- " + r.why());
  }

  static boolean olderOrSame(String a, String b) {
    String[] x = canonical(a).split("\\."), y = canonical(b).split("\\.");
    for (int i = 0; i < Math.max(x.length, y.length); i++) {
      int xi = i < x.length ? num(x[i]) : 0, yi = i < y.length ? num(y[i]) : 0;
      if (xi != yi) return xi < yi;
    }
    return true;
  }

  static int num(String s) {
    Matcher m = Pattern.compile("^([0-9]+)").matcher(s);
    return m.find() ? Integer.parseInt(m.group(1)) : 0;
  }

  static String latestBase() { return releaseBase(null); }

  static String releaseBase(String version) {
    String o = env("FLIXW_RELEASE_SOURCE");
    if (o != null && !o.isBlank()) return o.replaceAll("/+$", "") + "/";
    return version == null
       ? "https://github.com/wstein/flixw/releases/latest/download/"
       : "https://github.com/wstein/flixw/releases/download/v" + version + "/";
  }

  static final String RELEASES_API = "https://api.github.com/repos/wstein/flixw/releases?per_page=1";

  static String latestPrereleaseTag() {
    HttpRequest req = HttpRequest.newBuilder(URI.create(RELEASES_API))
        .timeout(Duration.ofSeconds(60))
        .header("User-Agent", "flixw/" + WRAPPER_VERSION)
        .header("Accept", "application/vnd.github+json")
        .build();
    try {
      HttpResponse<String> res = httpClient().send(req, HttpResponse.BodyHandlers.ofString());
      return res.statusCode() == 200 ? extractTagName(res.body()) : null;
    } catch (IOException e) {
      return null;
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return null;
    }
  }

  static String extractTagName(String json) {
    Matcher m = Pattern.compile("\"tag_name\"\\s*:\\s*\"([^\"]+)\"").matcher(json);
    return m.find() ? m.group(1) : null;
  }

  static String digestFor(String sums, String assetName) {
    String want = null;
    for (String line : sums.split("\r?\n")) {
      String[] f = line.trim().split("\\s+");
      if (f.length == 2 && sumsName(f[1]).equals(assetName)) want = f[0];
    }
    return want;
  }

  static String sumsName(String field) {
    return field.startsWith("*") ? field.substring(1) : field;
  }

  static List<String> publishedAssets(String sums) {
    List<String> out = new ArrayList<>();
    for (String line : sums.split("\r?\n")) {
      String[] f = line.trim().split("\\s+");
      String name = f.length == 2 ? sumsName(f[1]) : "";

      boolean companion = name.matches("flixw-[a-z0-9-]+\\.java")
              || name.equals(PICOCLI_ASSET);
      if (companion && !out.contains(name))
        out.add(name);
    }
    return out;
  }

  static int warmAssets(String sums, String version) {
    int warm = 0;
    for (String name : publishedAssets(sums)) {
      try {
        ensureAsset(name, version);
        warm++;
      } catch (Fail f) {
        System.err.println("flixw: note: could not pre-fetch " + name + "; it will be"
                + " fetched when first needed");
        tr("warm " + name + ": " + f.getMessage());
      }
    }
    if (warm > 0)
      System.err.println("flixw: " + warm + " companion asset" + (warm == 1 ? "" : "s")
              + " cached for " + canonical(version) + "; they need no network again");
    return warm;
  }

  static void upgradeWrapper(Path root, String to, boolean pre) {

    boolean named = to != null;
    if (pre) {
      String override = env("FLIXW_RELEASE_SOURCE");

      if (override == null || override.isBlank()) {
        String tag = latestPrereleaseTag();
        if (tag == null)
          throw w005("could not reach GitHub's releases API to find the newest"
              + " published release (pre-release or not)");
        to = strip(tag);
      }
    }
    String base = releaseBase(to);
    String sums = readSums(base);
    String want = digestFor(sums, "flixw.java");
    if (want == null || !want.matches("[0-9a-f]{64}"))
      throw w005("the published SHA256SUMS names no digest for flixw.java");

    Path current = root.resolve(WRAPPER_DIR).resolve("flixw.java");
    if (Files.isRegularFile(current) && sha256(current).equals(want)) {

      System.out.println("flixw " + WRAPPER_VERSION
              + " is the newest release. Nothing to do.");

      warmAssets(sums, WRAPPER_VERSION);
      return;
    }
    Path dir = null;
    try {
      dir = Files.createTempDirectory("flixw-upgrade-");
      Path fresh = dir.resolve("flixw.java");
      System.err.println("flixw: downloading flixw "
              + (to == null ? "(the latest release)" : to));
      if (base.startsWith("file://"))
        Files.copy(Paths.get(URI.create(base + "flixw.java")), fresh,
             StandardCopyOption.REPLACE_EXISTING);
      else download(base + "flixw.java", fresh);
      String got = sha256(fresh);
      if (!got.equals(want))
        throw w006("digest mismatch for the downloaded flixw.java"
            + "\n       published " + want + "\n       downloaded " + got);

      Matcher m = Pattern.compile("WRAPPER_VERSION\\s*=\\s*\"([^\"]+)\"")
               .matcher(Files.readString(fresh, StandardCharsets.UTF_8));
      String published = m.find() ? m.group(1) : null;

      boolean notNewer = published != null && olderOrSame(published, WRAPPER_VERSION);
      boolean same = published != null
             && canonical(published).equals(canonical(WRAPPER_VERSION));
      if (notNewer && to != null && !same)
        System.err.println("flixw: moving back from " + WRAPPER_VERSION + " to "
                + published + (named ? ", which you asked for by name"
                           : ", the newest published pre-release"));
      else if (notNewer && to != null) {

        System.out.println("flixw is already " + published + ". Nothing to do.");
        warmAssets(sums, published);
        return;
      } else if (notNewer) {
        System.out.println("flixw " + WRAPPER_VERSION + " is newer than the newest"
                + " release (" + published + "). Nothing to do.");

        if (same) warmAssets(sums, WRAPPER_VERSION);
        return;
      }
      System.err.println("flixw: " + WRAPPER_VERSION + " -> "
              + (published == null ? "the latest release" : published));

      Path javaExe = exeIn(System.getProperty("java.home"));

      Path installer = ensureAsset(SETUP_ASSET, published == null ? WRAPPER_VERSION : published);
      ProcessBuilder pb = new ProcessBuilder(javaExe.toString(), installer.toString(),
                         "setup", root.toString(), fresh.toString())
                  .inheritIO();

      pb.environment().remove("FLIXW_SOURCE");
      pb.environment().remove("FLIXW_RELAUNCHED");
      Process p = pb.start();
      int rc = awaitWithReaper(p);
      if (rc != 0) throw w009("the downloaded flixw failed to install (exit " + rc + ")");

      warmAssets(sums, published == null ? WRAPPER_VERSION : published);
    } catch (IOException e) {
      throw w007("cannot upgrade the wrapper: " + why(e));
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw w009("upgrade interrupted");
    } finally {
      if (dir != null) deleteTree(dir);
    }
  }

  static void wrapperNamespace(List<String> argv) {
    String op = argv.size() > 1 ? argv.get(1) : "--help";
    List<String> rest = argv.subList(Math.min(2, argv.size()), argv.size());
    switch (op) {
      case "--help" -> {
        if (!rest.isEmpty()) throw w008(wrapperUsage("'--help' takes no arguments"));
        helpTopic(List.of("wrapper"), null, null, null, null, List.of(), null, List.of(), true);
      }
      case "--version" -> {
        if (!rest.isEmpty()) throw w008(wrapperUsage("'--version' takes no arguments"));
        System.out.println("flixw " + WRAPPER_VERSION);
        System.out.println("stage0 " + (sourceLaunchPath() == null ? "compiled" : "source")
                + "  java " + Runtime.version());
      }
      case "--upgrade" -> {
        String to = null;
        boolean pre = false;
        for (String a : rest) {
          if (a.equals("--pre-release")) { pre = true; continue; }
          if (to != null)
            throw w008(wrapperUsage("'--upgrade' takes at most one version"));
          to = strip(a);
          if (!SEMVERISH.matcher(to).matches())
            throw w008(wrapperUsage("'" + a + "' is not a version"));
        }

        if (pre && to != null)
          throw w008(wrapperUsage("'--upgrade --pre-release' takes no version"));

        upgradeWrapper(findRoot(wrapperAnchor()), to, pre);
      }
      case "--install-jdk" -> {
        if (!rest.isEmpty()) throw w008(wrapperUsage("'--install-jdk' takes no arguments"));
        installJdkVerb(argv.subList(1, argv.size()));
      }
      case "--purge" -> {
        int days = 14;
        boolean yes = false, sawDays = false;
        for (String a : rest) {
          if (a.equals("--yes")) { yes = true; continue; }
          if (sawDays) throw w008(wrapperUsage("'--purge' takes one number of days"));
          try { days = Integer.parseInt(a); sawDays = true; }
          catch (NumberFormatException e) { throw w008(wrapperUsage("purge days must be a whole number")); }
        }
        if (days < 0) throw w008(wrapperUsage("purge days must not be negative"));
        purgeCache(days, yes);
      }

      case "--schema" -> {
        if (!rest.isEmpty()) throw w008(wrapperUsage("'--schema' takes no arguments"));
        System.out.print(lockSchemaJson());
      }

      default -> throw w008(wrapperUsage("unknown operation " + q(op)));
    }
  }

  static String wrapperUsage(String problem) {
    return "./flixw wrapper: " + problem
      + "\n       usage: ./flixw wrapper [--help | --version | --upgrade"
      + "\n                              | --install-jdk | --purge [days] [--yes] | --schema]"
      + "\n         --help         the routing table for this project"
      + "\n         --version      the wrapper version and how stage 0 was launched"
      + "\n         --upgrade [<version>]  move this project to the newest published"
      + "\n                        flixw, or to the release you name"
      + "\n                        (to repair the files it has: ./flixw doctor --fix)"
      + "\n         --pre-release  with --upgrade and no version, the newest published"
      + "\n                        release even if still finishing its own verification"
      + "\n                        (releases/latest skips it until that passes)"
      + "\n         --install-jdk  fetch a verified Temurin " + MIN_JAVA + " into the cache"
      + "\n         --purge [days] [--yes]  ask before deleting cache entries unused for"
      + "\n                        that many days, 14 by default"
      + "\n         --schema       the JSON Schema for " + WRAPPER_DIR + "/lock.toml, on stdout"
      + "\n       (a TAB-completion script is ./flixw completion <shell>)";
  }

  static final List<String> COMPLETION_SHELLS = List.of("bash", "zsh", "fish", "pwsh");

  static boolean completionEarly(List<String> args) {
    completionShell(args);
    Path root = null;
    try { root = findRoot(wrapperAnchor()); } catch (Fail ignored) { }
    Lock lock = null;
    if (root != null) try { lock = readLock(lockPath(root)); } catch (Fail ignored) { }
    List<String> cv = new ArrayList<>();
    if (lock != null) {
      Path vf = verbsFile(compilerPath(lock), lock.sha256());
      if (Files.isRegularFile(vf)) {
        try {
          cv.addAll(Files.readAllLines(vf, StandardCharsets.UTF_8));
          cv.removeIf(String::isBlank);
        } catch (IOException ignored) { }
      }
    }
    if (cv.contains("completion")) return false;
    completionScript(args, root, lock, null, null, cv, lock == null ? null : lock.sha256());
    return true;
  }

  static String completionShell(List<String> args) {
    List<String> shells = new ArrayList<>(args);
    if (shells.size() != 1)
      throw w008(COMPLETION_USAGE);
    String shell = shells.get(0);
    if (!COMPLETION_SHELLS.contains(shell))
      throw w008("./flixw completion: unknown shell " + q(shell)
          + "\n       " + COMPLETION_USAGE);
    return shell;
  }

  static void completionScript(List<String> args, Path root, Lock lock, Path jar, Jvm jvm,
                List<String> compilerVerbs, String identity) {
    String shell = completionShell(args);
    helpTopic(List.of("completion", shell), root, lock, jar, jvm, compilerVerbs, identity,
         List.of(), false);
  }

  static final String COMPLETION_USAGE =
     "usage: ./flixw completion <" + String.join("|", COMPLETION_SHELLS) + ">"
    + "\n       the script describes the compiler this project has pinned, so it needs"
    + "\n       regenerating after a re-pin";

  static final String JDK_ASSET = "flixw-jdk.java";

  static final String SETUP_ASSET = "flixw-setup.java";

  static final String INSPECT_ASSET = "flixw-inspect.java";

  static final String HELP_ASSET = "flixw-help.java";

  static final String EXAMPLES_ASSET = "flixw-examples.java";

  static final String LOCAL_ASSET = "flixw-local.java";

  static final String PICOCLI_VERSION = "4.7.8";
  static final String PICOCLI_ASSET = "picocli-" + PICOCLI_VERSION + ".jar";

  static void assetHelp(String assetName, String selector) {
    int rc = runAsset(ensureAsset(assetName), ensureAsset(PICOCLI_ASSET), List.of(selector));
    if (rc != 0) throw w009("cannot render help for " + assetName + " (exit " + rc + ")");
  }

  static String storedHelp(String identity) {
    try {
      String help = Files.readString(helpFile(identity), StandardCharsets.UTF_8);
      for (String l : Files.readAllLines(helpMetaFile(identity), StandardCharsets.UTF_8))
        if (l.startsWith("content_sha256="))
          return sha256(help.getBytes(StandardCharsets.UTF_8)).equals(l.substring(15))
             ? help : null;
    } catch (IOException ignored) { }
    return null;
  }

  static String helpContext(Path root, Lock lock, Path jar, Jvm jvm, List<String> compilerVerbs,
               String identity, boolean override) {
    if (compilerVerbs == null) compilerVerbs = List.of();
    StringBuilder b = new StringBuilder();
    b.append("flixwVersion=").append(WRAPPER_VERSION).append('\n');
    b.append("projectRoot=").append(root == null ? "" : root).append('\n');
    b.append("cacheHome=").append(cacheHome()).append('\n');
    b.append("compilerVersion=").append(lock == null ? "" : lock.version()).append('\n');

    b.append("upstream=").append(isUpstream(lock, override)).append('\n');
    b.append("compilerJar=").append(jar == null ? "" : jar).append('\n');
    b.append("javaExe=").append(jvm == null ? "" : jvm.exe()).append('\n');
    b.append("helpFile=")
    .append(identity == null || storedHelp(identity) == null ? "" : helpFile(identity))
    .append('\n');
    b.append("compilerVerbs=").append(String.join(" ", compilerVerbs)).append('\n');

    List<String> fallback = new ArrayList<>(WRAPPER_VERBS);
    for (String v : BUILTIN_VERBS) if (!fallback.contains(v)) fallback.add(v);
    fallback.sort(null);
    b.append("fallbackVerbs=").append(String.join(",", fallback)).append('\n');
    List<String> wv = new ArrayList<>(WRAPPER_VERBS);
    wv.removeAll(compilerVerbs);
    b.append("wrapperVerbs=").append(String.join(" ", wv)).append('\n');
    b.append('\n').append("plugins:").append('\n');
    if (lock != null)
      for (Map.Entry<String, PluginDep> e : lock.plugins().entrySet())
        b.append(e.getKey()).append('\t').append(e.getValue().version()).append('\t')
        .append(e.getValue().sha256()).append('\t')
        .append(e.getValue().source() == null ? "" : e.getValue().source()).append('\t')
        .append(e.getValue().description() == null ? "" : e.getValue().description())
        .append('\t')
        .append(e.getValue().command() == null ? "" : e.getValue().command())
        .append('\n');
    b.append('\n').append("tasks:").append('\n');
    if (root != null)
      for (Map.Entry<String, String> e : readTasks(root).entrySet())
        b.append(esc(e.getKey())).append('\t').append(esc(e.getValue())).append('\n');
    return b.toString();
  }

  static String esc(String s) {
    return s == null ? "" : s.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n")
                .replace("\r", "\\r");
  }

  static void helpTopic(List<String> rest, Path root, Lock lock, Path jar, Jvm jvm,
             List<String> compilerVerbs, String identity, List<String> jvmOpts,
             boolean degrade) {
    try {
      System.exit(renderHelp(rest, root, lock, jar, jvm, compilerVerbs, identity, jvmOpts));
    } catch (IOException | RuntimeException e) {
      if (!degrade) throw e instanceof RuntimeException r ? r
                : w005("cannot run the completion generator: " + why((IOException) e));
      offlineHelp(identity, e);
    }
  }

  static int renderHelp(List<String> rest, Path root, Lock lock, Path jar, Jvm jvm,
             List<String> compilerVerbs, String identity, List<String> jvmOpts)
      throws IOException {
    Path ctx = Files.createTempFile("flixw-help-", ".txt");
    try {
      Path asset = ensureAsset(HELP_ASSET), picocli = ensureAsset(PICOCLI_ASSET);
      Files.writeString(ctx, helpContext(root, lock, jar, jvm, compilerVerbs, identity,
                        env("FLIX_JAR") != null),
               StandardCharsets.UTF_8);
      List<String> a = new ArrayList<>(List.of(ctx.toString()));
      a.addAll(rest.subList(0, Math.min(3, rest.size())));

      a.addAll(jvmOpts);
      return runAsset(asset, picocli, a);
    } finally {
      try { Files.deleteIfExists(ctx); } catch (IOException ignored) { }
    }
  }

  static boolean compilerVerbHelp(String verb, Path root, Lock lock, Path jar, Jvm jvm,
                  List<String> compilerVerbs, String identity,
                  List<String> jvmOpts) {
    try {
      return renderHelp(List.of("flix-direct", verb), root, lock, jar, jvm,
               compilerVerbs, identity, jvmOpts) == 0;
    } catch (IOException | RuntimeException e) {
      tr("cannot render compiler help for " + verb + ": " + why(e));
      return false;
    }
  }

  static void offlineHelp(String identity, Exception e) {
    System.err.println("flixw: the help renderer could not be fetched: "
            + (e.getMessage() == null ? e.toString() : e.getMessage()));
    System.err.println("       what follows came from this wrapper and the cache, offline.");
    System.err.println();
    wrapperHelp();
    String help = identity == null ? null : storedHelp(identity);
    if (help == null) return;
    System.out.println();
    System.out.println("---- the pinned compiler's own help, as captured ----");
    System.out.println();
    System.out.print(help.endsWith("\n") ? help : help + "\n");
  }

  static void runSetupAsset(List<String> args) {
    int rc = runAsset(ensureAsset(SETUP_ASSET), null, args);

    if (rc != 0) System.exit(rc);
  }

  static final String SHIM_SHA256 =
    "0862cc2ef47012a48df6d585cfe659fec887cc4af1b46b792686734132f00dfa";
  static final String CMD_SHA256 =
    "03b5b4740e73ea426ff82799185127cc24bb9b34a1419b4f6b2434c5f6352495";

  static String assetSourceBase(String version) {
    String o = env("FLIXW_ASSET_SOURCE");
    if (o != null) return o.replaceAll("/+$", "") + "/";
    return "https://github.com/wstein/flixw/releases/download/v" + canonical(version) + "/";
  }

  static Path assetDir(String version) {
    return cacheHome().resolve("wrapper").resolve("assets").resolve(canonical(version));
  }

  static String readSums(String base) {
    try {
      return base.startsWith("file://")
        ? Files.readString(Paths.get(URI.create(base + "SHA256SUMS")), StandardCharsets.UTF_8)
        : httpGet(base + "SHA256SUMS");
    } catch (IOException e) {
      throw w005("cannot read " + redact(base) + "SHA256SUMS: " + why(e) + fileUrlHint(base));
    }
  }

  static String fileUrlHint(String base) {
    if (!isWindows() || !base.startsWith("file://")) return "";
    String p = base.substring("file://".length());
    return p.matches("/[A-Za-z]/.*")
      ? "\n       on Windows a file:// url needs the drive letter: file:///"
       + Character.toUpperCase(p.charAt(1)) + ":" + p.substring(2)
       + "\n       (a Git Bash path like " + p.substring(0, 3) + "... is not one)"
      : "";
  }

  static Path ensureAsset(String name) { return ensureAsset(name, WRAPPER_VERSION); }

  static Path ensureAsset(String name, String version) {
    Path dir = assetDir(version);
    Path asset = dir.resolve(name), marker = dir.resolve(name + ".sha256");
    if (Files.isRegularFile(asset) && Files.isRegularFile(marker)) {
      try {
        if (sha256(asset).equals(Files.readString(marker, StandardCharsets.UTF_8).trim())) {
          markUsed("asset/" + canonical(version));
          return asset;
        }
      } catch (IOException ignored) { }

    }
    String base = assetSourceBase(version);
    String sums = readSums(base);
    String want = digestFor(sums, name);
    if (want == null || !want.matches("[0-9a-f]{64}"))
      throw w005("no published flixw " + version + " release names " + name
          + "\n       run: ./flixw wrapper --upgrade   (or wait for this version to be released)");
    try {
      Files.createDirectories(dir);
      Path tmp = Files.createTempFile(dir, ".asset-", ".part");
      try {
        if (base.startsWith("file://"))
          Files.copy(Paths.get(URI.create(base + name)), tmp,
               StandardCopyOption.REPLACE_EXISTING);
        else download(base + name, tmp);
        String got = sha256(tmp);
        if (!got.equals(want))
          throw w006("digest mismatch for " + name
              + "\n       expected " + want + "\n       actual   " + got);
        try { Files.move(tmp, asset, StandardCopyOption.ATOMIC_MOVE); }

        catch (IOException e) { if (!Files.isRegularFile(asset)) throw e;
          if (!sha256(asset).equals(want)) throw w006(name + " lost a cache race to bytes that are not " + want); }
      } finally {
        try { Files.deleteIfExists(tmp); } catch (IOException ignored) { }
      }

      writeAtomic(marker, want);
    } catch (IOException e) {
      throw w007("cannot cache " + name + ": " + why(e));
    }
    markUsed("asset/" + canonical(version));
    return asset;
  }

  public static void main(String[] args) {
    try { realMain(new ArrayList<>(Arrays.asList(args))); }
    catch (Fail f) {
      System.err.println(f.code + ": " + f.getMessage());
      System.exit(f.exit);
    }
  }

  static void realMain(List<String> argv) {
    tr("stage 0 entered");
    String first = argv.isEmpty() ? null : argv.get(0);

    if ("wrapper".equals(first)) { wrapperNamespace(argv); return; }

    if ("plugin".equals(first) && argv.size() >= 2) {
      List<String> rest = argv.subList(2, argv.size());
      switch (argv.get(1)) {
        case "list" -> { pluginList(lockIfAny()); return; }
        case "remove" -> { pluginRemove(rest); return; }
        case "install" -> { pluginInstall(rootIfAny(), rest); return; }
        case "upgrade" -> { pluginUpgrade(rootIfAny(), rest); return; }
        default -> { }
      }
    }

    if (first != null && first.startsWith("--wrapper-"))
      throw w008(wrapperUsage("unknown launcher flag " + q(first)
          + "\n       flixw's own operations moved under one verb"));

    if ("completion".equals(first) && completionEarly(argv.subList(1, argv.size())))
      return;

    Path anchor = wrapperAnchor();

    validateDistUrl();

    String backend = env("FLIX_BACKEND");
    if (backend != null && !backend.equals("wrapper") && !backend.equals("compiler"))
      throw w008("FLIX_BACKEND=" + q(backend) + " is not a known backend;"
          + " use 'wrapper' or 'compiler'");
    boolean forcedWrapper = "wrapper".equals(backend);
    boolean forcedCompiler = "compiler".equals(backend);

    Path root = findRoot(anchor);
    tr("root " + root);
    Path lockFile = lockPath(root);

    Lock lock = null;
    Fail lockError = null;
    if (Files.isRegularFile(lockFile)) {
      try { lock = readLock(lockFile); }
      catch (Fail f) { lockError = f; }
    }

    String mv = null;
    Fail manifestError = null;
    try { mv = manifestVersion(root.resolve("flix.toml")); }
    catch (Fail f) { manifestError = f; }

    String drift = (lock != null && mv != null
            && !olderOrSame(triple(mv), triple(lock.version())))
      ? "flix.toml asks for Flix " + mv + " or newer, but " + WRAPPER_DIR
       + "/lock.toml pins " + lock.version()
       + "\n       run: ./flixw pin " + triple(mv) + " (or lower the requirement)"
      : null;

    boolean bareHelp = ("--help".equals(first) || "-h".equals(first)) && argv.size() == 1;

    if ((lock == null || drift != null || manifestError != null) && first != null && !forcedCompiler
      && (WRAPPER_VERBS.contains(first) || bareHelp)) {
      if (lockError != null)
        System.err.println("flixw: warning: " + lockError.getMessage().split("\n")[0]);
      if (manifestError != null)
        System.err.println("flixw: warning: " + manifestError.getMessage().split("\n")[0]);
      if (drift != null) System.err.println("flixw: warning: " + drift.split("\n")[0]);
      routingNotice(first, lock == null ? "none" : lock.version());
      if (first.equals("pin")) {
        List<String> rest = argv.subList(1, argv.size());
        if (wantsHelp(rest)) System.out.println(PIN_USAGE);
        else pin(root, parsePin(rest, lock));
      } else if (bareHelp) {
        wrapperVerb("help", List.of(), root, lock, null, null, null, null);
      }
      else
        wrapperVerb(first, argv.subList(1, argv.size()), root, lock, null, null, null, null);
      return;
    }
    if (lockError != null) throw lockError;
    if (manifestError != null) throw manifestError;
    if (lock == null)
      throw w002("no " + lockFile + "\n       run: ./flixw pin <version>");
    if (drift != null) throw w002(drift);

    if ("pin".equals(first) && !forcedCompiler) {
      routingNotice("pin", lock.version());
      List<String> rest = argv.subList(1, argv.size());
      if (wantsHelp(rest)) System.out.println(PIN_USAGE);
      else pin(root, parsePin(rest, lock));
      return;
    }

    Jvm jvm;
    try {
      jvm = selectJava(lock == null ? null : lock.java());
    } catch (Fail e) {
      if (!diagnostic(first)) throw e;
      System.err.println(e.getMessage());
      System.err.println("flixw: continuing on the JVM this wrapper is running under,"
              + " because " + q(first) + " reports state rather than compiling");
      jvm = runningJvm();
    }
    tr("java " + jvm.exe() + " (" + jvm.feature() + ")");
    recordJava(root, jvm.exe());
    if (relaunch(jvm, argv)) return;
    List<String> opts = jvmOpts();

    Path jar;
    String fj = env("FLIX_JAR");
    boolean override = fj != null;
    if (override) {
      jar = Paths.get(fj).toAbsolutePath();
      if (!Files.isRegularFile(jar)) throw w008("FLIX_JAR=" + fj + " is not a file");
      System.err.println("flixw: note: FLIX_JAR override in use; the JAR is NOT digest-verified"
              + " and this run is not stock-compatibility evidence");
      reportOverrideGap(lock, jar);
    } else jar = acquire(lock);

    String verbId = verbIdentity(jar, lock, override);
    List<String> compilerVerbs = verbs(jvm.exe(), jar, verbId);
    tr("verbs " + compilerVerbs.size());

    if (lock != null)
      reportVersionGap("the pinned compiler", lock.version(), lock.reportedVersion());
    selfCompile(selfSource());

    boolean toCompiler; List<String> forward = argv;

    String pluginOwner = first == null || compilerVerbs.contains(first)
              || WRAPPER_VERBS.contains(first) ? null : commandOwner(lock, first);
    if (forcedCompiler) {
      toCompiler = true;
      if ("--".equals(first)) forward = argv.subList(1, argv.size());
    } else if (forcedWrapper && first != null && WRAPPER_VERBS.contains(first)) {
      toCompiler = false;
    } else if ("--".equals(first)) {
      toCompiler = true; forward = argv.subList(1, argv.size());
    } else if (first != null && compilerVerbs.contains(first)) {
      toCompiler = true;
      if ("run".equals(first) && isUpstream(lock, override)) forward = autoRunBoundary(argv);
    } else if (first != null && WRAPPER_VERBS.contains(first)) {
      toCompiler = false;
    } else if (pluginOwner != null) {
      toCompiler = false;
    } else {
      toCompiler = true;
    }

    if (!toCompiler && "help".equals(first)
      && localHelpTopic(forward.subList(Math.min(1, forward.size()), forward.size())))
      return;
    if (!toCompiler && "help".equals(first)
      || (!forcedCompiler && ("--help".equals(first) || "-h".equals(first)) && argv.size() == 1)) {

      helpTopic(forward.subList(Math.min(1, forward.size()), forward.size()),
           root, lock, jar, jvm, compilerVerbs, verbId, opts, true);
      return;
    }

    if (toCompiler && !forcedCompiler && first != null && compilerVerbs.contains(first)
      && exactCompilerHelp(forward)
      && compilerVerbHelp(first, root, lock, jar, jvm, compilerVerbs, verbId, opts))
      return;

    if (!toCompiler && pluginOwner != null && !WRAPPER_VERBS.contains(first)) {
      runDeclaredPlugin(pluginOwner, first, forward.subList(1, forward.size()),
               root, lock, jar, jvm);
      return;
    }
    if (!toCompiler) {
      if (forcedWrapper && compilerVerbs.contains(first) && trace())
        System.err.println("flixw: " + q(first) + " \u2192 wrapper " + WRAPPER_VERSION
                + " (forced by FLIX_BACKEND=wrapper; compiler " + lock.version()
                + " also implements it)");
      else routingNotice(first, lock.version());
      wrapperVerb(first, forward.subList(1, forward.size()), root, lock, jar, jvm, compilerVerbs, verbId);
      return;
    }
    if (first != null && lock != null && compilerVerbs.contains(first)
      && commandOwner(lock, first) != null)
      System.err.println("flixw: note: compiler " + lock.version() + " implements "
              + q(first) + "; plugin " + commandOwner(lock, first)
              + " no longer answers it -- run: ./flixw plugin "
              + commandOwner(lock, first));
    if (first != null && WRAPPER_VERBS.contains(first) && compilerVerbs.contains(first))
      System.err.println("flixw: note: compiler " + lock.version() + " now implements "
              + q(first) + "; the wrapper implementation is deprecated"
              + " and will be removed in the next wrapper release");

    launch(jvm.exe(), opts, jar, forward);
  }

  static boolean exactCompilerHelp(List<String> argv) {
    return argv.size() == 2 && ("--help".equals(argv.get(1)) || "-h".equals(argv.get(1)));
  }

  static void routingNotice(String verb, String compilerVersion) {
    if (!trace()) return;
    System.err.println("flixw: " + q(verb) + " \u2192 wrapper " + WRAPPER_VERSION
            + " (pinned compiler " + compilerVersion + " does not implement it)");
  }

  static void wrapperHelp() {
    System.out.println("""
            flixw %s -- repository-local Flix bootstrap

              ./flixw help            full help (fetches the verified renderer on a cold cache)
              ./flixw wrapper --help  wrapper reference
              ./flixw -- --help       stock compiler help, unedited
            """.formatted(WRAPPER_VERSION));
  }

  static Path sourceLaunchPath() {
    try {
      Path loc = Paths.get(flixw.class.getProtectionDomain().getCodeSource()
                .getLocation().toURI());
      if (Files.isRegularFile(loc) && loc.toString().endsWith(".java")) return loc;
    } catch (Exception ignored) { }
    return null;
  }

  static Path selfSource() {
    Path launched = sourceLaunchPath();
    if (launched != null) return launched;
    String s = env("FLIXW_SOURCE");
    if (s != null) return Paths.get(s);
    try {
      Path loc = Paths.get(flixw.class.getProtectionDomain().getCodeSource().getLocation().toURI());
      Path p = loc.resolve("source.path");
      if (Files.isRegularFile(p)) return Paths.get(Files.readString(p).trim());
    } catch (Exception ignored) { }
    return null;
  }

  static void recordJava(Path root, Path exe) {
    Path marker = root.resolve(WRAPPER_DIR).resolve("local").resolve("java");
    try {

      String want = exe.toAbsolutePath().normalize() + System.lineSeparator();
      if (Files.isRegularFile(marker)
        && Files.readString(marker, StandardCharsets.UTF_8).equals(want)) return;
      Files.createDirectories(marker.getParent());
      writeAtomic(marker, want);
    } catch (IOException | RuntimeException ignored) { }
  }

  static boolean relaunch(Jvm jvm, List<String> argv) {
    Path cur = ProcessHandle.current().info().command().map(Paths::get).orElse(null);
    if (cur != null && cur.equals(jvm.exe())) return false;
    if (env("FLIXW_RELAUNCHED") != null) return false;
    Path src = selfSource();
    if (src == null) return false;
    List<String> cmd = new ArrayList<>(List.of(jvm.exe().toString(), src.toString()));
    cmd.addAll(argv);
    try {
      ProcessBuilder pb = new ProcessBuilder(cmd).inheritIO();
      pb.environment().put("FLIXW_RELAUNCHED", "1");
      System.exit(awaitWithReaper(pb.start()));
    } catch (IOException | InterruptedException e) {
      throw w004("relaunch under " + jvm.exe() + " failed: " + e.getMessage());
    }
    return true;
  }

  static int awaitWithReaper(Process p) throws InterruptedException {
    Thread hook = new Thread(() -> {
      if (!p.isAlive()) return;

      List<ProcessHandle> below = p.descendants().toList();
      p.destroy();
      below.forEach(ProcessHandle::destroy);
      try {

        if (!p.waitFor(10, TimeUnit.SECONDS)) {
          p.destroyForcibly();
          p.waitFor(5, TimeUnit.SECONDS);
        }
      } catch (InterruptedException ignored) {
        Thread.currentThread().interrupt();
      }
      below.forEach(h -> { if (h.isAlive()) h.destroyForcibly(); });
    }, "flixw-reaper");
    Runtime.getRuntime().addShutdownHook(hook);
    try {
      return p.waitFor();
    } finally {
      try { Runtime.getRuntime().removeShutdownHook(hook); }
      catch (IllegalStateException ignored) { }
    }
  }

  static Path javaHomeOf(Path exe) {
    Path bin = exe.getParent();
    return bin == null ? null : bin.getParent();
  }

  static Map<String, String> pluginEnv(Path root, Lock lock, Jvm jvm, Path compilerJar,
                    String pluginName, ResolvedPlugin p, List<String> args) {
    Map<String, String> env = new LinkedHashMap<>();
    env.put("FLIXW_ABI_VERSION", "1");
    env.put("FLIXW_PROJECT_ROOT", root.toString());
    env.put("FLIXW_CACHE_HOME", cacheHome().toString());
    if (lock != null) {
      env.put("FLIXW_COMPILER_VERSION", lock.version());
      env.put("FLIXW_COMPILER_REPO", lock.repo() == null ? UPSTREAM_REPO : lock.repo());
      env.put("FLIXW_COMPILER_SHA256", lock.sha256());
    }
    if (compilerJar != null) env.put("FLIXW_COMPILER_JAR", compilerJar.toString());
    if (jvm != null) {
      Path home = javaHomeOf(jvm.exe());
      if (home != null) env.put("FLIXW_JAVA_HOME", home.toString());
    }
    env.put("FLIXW_PLUGIN_NAME", pluginName);
    env.put("FLIXW_PLUGIN_VERSION", p.version());
    env.put("FLIXW_PLUGIN_SHA256", p.sha256());
    env.put("FLIXW_PLUGIN_CACHE", pluginCacheDir(pluginName).toString());
    env.put("FLIXW_CONTEXT", writeContextFile(root, lock, jvm, compilerJar, pluginName, p, args).toString());
    return env;
  }

  static Path writeContextFile(Path root, Lock lock, Jvm jvm, Path compilerJar,
                String pluginName, ResolvedPlugin p, List<String> args) {
    StringBuilder b = new StringBuilder();
    b.append("{\n");
    b.append("  \"abiVersion\": 1,\n");
    b.append("  \"flixwVersion\": ").append(jsonString(WRAPPER_VERSION)).append(",\n");
    b.append("  \"projectRoot\": ").append(jsonString(root.toString())).append(",\n");
    b.append("  \"cacheHome\": ").append(jsonString(cacheHome().toString())).append(",\n");
    if (lock == null) {
      b.append("  \"compiler\": null,\n");
    } else {
      b.append("  \"compiler\": {\n");
      b.append("    \"repo\": ")
      .append(jsonString(lock.repo() == null ? UPSTREAM_REPO : lock.repo())).append(",\n");
      b.append("    \"version\": ").append(jsonString(lock.version())).append(",\n");
      b.append("    \"sha256\": ").append(jsonString(lock.sha256())).append(",\n");
      b.append("    \"jar\": ")
      .append(compilerJar == null ? "null" : jsonString(compilerJar.toString())).append("\n");
      b.append("  },\n");
    }
    if (jvm == null) {
      b.append("  \"java\": null,\n");
    } else {
      Path home = javaHomeOf(jvm.exe());
      b.append("  \"java\": {\n");
      b.append("    \"home\": ").append(home == null ? "null" : jsonString(home.toString())).append(",\n");
      b.append("    \"feature\": ").append(jvm.feature()).append("\n");
      b.append("  },\n");
    }
    b.append("  \"plugin\": {\n");
    b.append("    \"name\": ").append(jsonString(pluginName)).append(",\n");
    b.append("    \"version\": ").append(jsonString(p.version())).append(",\n");
    b.append("    \"sha256\": ").append(jsonString(p.sha256())).append(",\n");
    b.append("    \"cache\": ").append(jsonString(pluginCacheDir(pluginName).toString()))
    .append("\n");
    b.append("  },\n");
    b.append("  \"args\": ").append(jsonArray(args)).append("\n");
    b.append("}\n");
    Path dir = pluginsDir();
    try {
      Files.createDirectories(dir);
      Path f = Files.createTempFile(dir, ".context-", ".json");
      Files.writeString(f, b.toString(), StandardCharsets.UTF_8);
      Runtime.getRuntime().addShutdownHook(new Thread(() -> {
        try { Files.deleteIfExists(f); } catch (IOException ignored) { }
      }));
      return f;
    } catch (IOException e) {
      throw w009("cannot write plugin context: " + why(e));
    }
  }

  static void runArtifact(Path artifact, Path javaExe, Path compilerJar, List<String> args,
              Map<String, String> env) {
    String name = artifact.getFileName().toString();
    List<String> cmd = new ArrayList<>();
    cmd.add(javaExe.toString());
    if (name.endsWith(".jar")) {
      cmd.add("-jar"); cmd.add(artifact.toString());
      cmd.addAll(args);
    } else if (name.endsWith(".java")) {
      cmd.add(artifact.toString());
      cmd.addAll(args);
    } else if (name.endsWith(".flix")) {
      if (compilerJar == null)
        throw w009("plugin " + q(name) + " is a .flix plugin, but this project has"
            + " no compiler pinned\n       run: ./flixw pin <version>");
      if (!args.isEmpty())
        throw w009("plugin " + q(name) + " is a .flix plugin: it cannot receive"
            + " arguments (stock Flix has no way to pass any to a standalone"
            + " file)\n       args given: " + String.join(" ", args));
      cmd.add("-jar"); cmd.add(compilerJar.toString());
      cmd.add(artifact.toString());
    } else {
      throw w009("plugin artifact " + q(name) + " is not .jar, .java or .flix");
    }
    tr("exec " + String.join(" ", cmd));
    try {
      ProcessBuilder pb = new ProcessBuilder(cmd).inheritIO();
      pb.environment().putAll(env);
      System.exit(awaitWithReaper(pb.start()));
    } catch (IOException e) {
      throw w005("cannot launch " + artifact + ": " + e.getMessage());
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      System.exit(130);
    }
  }

  static List<String> autoRunBoundary(List<String> argv) {
    if (argv.size() < 2 || argv.get(1).startsWith("-")) return argv;
    List<String> out = new ArrayList<>(argv.size() + 1);
    out.add(argv.get(0));
    out.add("--");
    out.addAll(argv.subList(1, argv.size()));
    return out;
  }

  static void launch(Path javaExe, List<String> opts, Path jar, List<String> args) {
    List<String> cmd = new ArrayList<>();
    cmd.add(javaExe.toString());
    cmd.addAll(opts);
    cmd.add("-jar"); cmd.add(jar.toString());
    cmd.addAll(args);
    tr("exec " + String.join(" ", cmd));
    try {
      System.exit(awaitWithReaper(new ProcessBuilder(cmd).inheritIO().start()));
    } catch (IOException e) {
      throw w005("cannot launch " + jar + ": " + e.getMessage());
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      System.exit(130);
    }
  }
}
