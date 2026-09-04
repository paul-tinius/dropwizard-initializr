#!/usr/bin/env bash
# Dropwizard Initializr — Spring Initializr-style project generator for Dropwizard.
# Compatible with Bash 3.2 (macOS /bin/bash).
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="1.2.0"

DEFAULT_DW_VERSION="5.0.2"
DEFAULT_JAVA_VERSION="17"
DEFAULT_GROUP="com.example"
DEFAULT_ARTIFACT="demo"
DEFAULT_DESCRIPTION="A Dropwizard service"
DEFAULT_BUILD="maven"
DEFAULT_DEPS="testing"

# Suggested current lines. Any 3.0.x / 4.0.x / 5.0.x version string is accepted.
DW_VERSION_5="5.0.2"
DW_VERSION_4="4.0.17"
DW_VERSION_3="3.0.17"

MAVEN_COMPILER_PLUGIN="3.14.0"
MAVEN_SHADE_PLUGIN="3.6.1"
MAVEN_JAR_PLUGIN="3.4.2"
MAVEN_SUREFIRE_PLUGIN="3.5.3"
SHADOW_PLUGIN="8.3.8"
H2_VERSION="2.3.232"
POSTGRES_VERSION="42.7.7"
MYSQL_VERSION="9.3.0"
ASSERTJ_VERSION="3.27.4"
JUNIT_JUPITER_VERSION="5.13.4"
JUNIT_PLATFORM_VERSION="1.13.4"

TYPE=""
DW_VERSION=""
JAVA_VERSION=""
GROUP=""
ARTIFACT=""
NAME=""
DESCRIPTION=""
PACKAGE=""
CLASS_PREFIX=""
DEPS=""
CUSTOM_DEPS=""
UNKNOWN_NOTES=""
OUTPUT=""
FORCE="false"
ZIP="false"
GIT_INIT="false"
DOCKER="false"
INTERACTIVE="auto"
LIST_ONLY="false"
UI_MODE="false"
UI_PORT="8088"

C_RESET=""
C_BOLD=""
C_DIM=""
C_CYAN=""
C_GREEN=""
C_YELLOW=""
C_RED=""
C_BLUE=""

if [ -t 1 ]; then
  C_RESET="$(printf '\033[0m')"
  C_BOLD="$(printf '\033[1m')"
  C_DIM="$(printf '\033[2m')"
  C_CYAN="$(printf '\033[36m')"
  C_GREEN="$(printf '\033[32m')"
  C_YELLOW="$(printf '\033[33m')"
  C_RED="$(printf '\033[31m')"
  C_BLUE="$(printf '\033[34m')"
fi

usage() {
  cat <<EOF
${C_BOLD}Dropwizard Initializr${C_RESET} ${C_DIM}v${SCRIPT_VERSION}${C_RESET}
Generate a production-ready Dropwizard project, in the same spirit as start.spring.io.

${C_BOLD}USAGE${C_RESET}
  ${SCRIPT_NAME} [options]
  ${SCRIPT_NAME} --defaults
  ${SCRIPT_NAME} --list

${C_BOLD}PROJECT METADATA${C_RESET}
  --group <id>              Maven/Gradle groupId              [${DEFAULT_GROUP}]
  --artifact <id>           Artifact / directory name         [${DEFAULT_ARTIFACT}]
  --name <name>             Display name / class prefix       [PascalCase(artifact)]
  --class-name <Name>       Application class prefix override
  --description <text>      Project description
  --package <name>          Java package                      [group + artifact]
  --java-version <ver>      11 | 17 | 21 | 25                 [${DEFAULT_JAVA_VERSION}]
  --dw-version <ver>        Dropwizard version                [${DEFAULT_DW_VERSION}]
  --build <type>            maven | gradle                    [${DEFAULT_BUILD}]
  --dependencies <ids>      Catalog ids, aliases, or Maven coordinates
                            group:artifact[:version[:scope]]  [${DEFAULT_DEPS}]

${C_BOLD}OUTPUT${C_RESET}
  --output <dir>            Destination directory             [./<artifact>]
  --force                   Overwrite an existing directory
  --zip                     Also pack the project as <artifact>.zip
  --git                     git init + initial commit
  --docker                  Include a Dockerfile
  --defaults                Non-interactive; use flags + defaults
  --interactive             Force the wizard even when flags are set
  --list                    List available dependencies and exit
  --ui                      Open the start.spring.io-style web UI
  --port <n>                UI port (with --ui)               [8088]
  -h, --help                Show this help

${C_BOLD}EXAMPLES${C_RESET}
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --defaults
  ${SCRIPT_NAME} --group com.acme --artifact hello-world --build gradle \\
      --dependencies auth,hibernate,migrations,postgresql --docker --git
  ${SCRIPT_NAME} --dw-version ${DW_VERSION_4} --java-version 17 --dependencies jdbi3,h2
  ${SCRIPT_NAME} --dependencies auth,com.google.guava:guava:33.4.8-jre,dropwizard-kafka
  ${SCRIPT_NAME} --ui

${C_BOLD}DEPENDENCY ALIASES${C_RESET}
  jpa, data-jpa, orm  -> hibernate
  jdbc, jdbi          -> jdbi3
  liquibase           -> migrations
  security            -> auth
  postgres            -> postgresql
  mysql, mariadb      -> mysql
  views               -> views-freemarker
  web, core           -> (always included)

${C_BOLD}UNKNOWN / CUSTOM DEPENDENCIES${C_RESET}
  Catalog typos (edit distance 1, or a unique prefix of 4+ chars) are
  auto-corrected. Anything else is added as a Maven/Gradle coordinate:
    group:artifact[:version[:scope]]   explicit coordinate
    dropwizard-kafka                   io.dropwizard:dropwizard-kafka
    redis                              io.dropwizard:dropwizard-redis
  Custom entries are wired into the build. No sample Java is generated for them.
EOF
}

die() {
  printf '%s%s%s\n' "${C_RED}" "error: $*" "${C_RESET}" >&2
  exit 1
}

info() {
  printf '%s%s%s\n' "${C_CYAN}" "$*" "${C_RESET}"
}

ok() {
  printf '%s%s%s\n' "${C_GREEN}" "$*" "${C_RESET}"
}

warn() {
  printf '%s%s%s\n' "${C_YELLOW}" "$*" "${C_RESET}"
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

trim() {
  printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# "hello-world" / "Hello World" / "hello_world" -> HelloWorld
to_pascal() {
  local input="$1"
  local cleaned out="" word first rest
  cleaned="$(printf '%s' "$input" | sed -E 's/[^A-Za-z0-9]+/ /g')"
  local IFS=' '
  # shellcheck disable=SC2086
  set -- $cleaned
  for word in "$@"; do
    [ -z "$word" ] && continue
    first="$(printf '%s' "$word" | cut -c1 | tr '[:lower:]' '[:upper:]')"
    rest="$(printf '%s' "$word" | cut -c2-)"
    out="${out}${first}${rest}"
  done
  printf '%s' "$out"
}

to_artifact_suffix() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '_.-'
}

has_dep() {
  local needle haystack
  needle="$(lower "$1")"
  haystack="$(lower "$DEPS" | tr -d ' ')"
  case ",${haystack}," in
    *",${needle},"*) return 0 ;;
    *) return 1 ;;
  esac
}

append_dep() {
  local d
  d="$(lower "$(trim "$1")")"
  [ -z "$d" ] && return 0
  case "$d" in
    none|core|web) return 0 ;;
  esac
  if has_dep "$d"; then
    return 0
  fi
  if [ -z "$DEPS" ]; then
    DEPS="$d"
  else
    DEPS="${DEPS},${d}"
  fi
}

note_unknown() {
  UNKNOWN_NOTES="${UNKNOWN_NOTES}$1
"
  warn "$1"
}

catalog_ids() {
  printf '%s\n' testing auth client forms assets views-freemarker views-mustache http2 \
    hibernate jdbi3 migrations h2 postgresql mysql json-logging metrics-graphite docker
}

is_coord_part() {
  echo "$1" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9_.-]*$'
}

char_at() {
  printf '%s' "$1" | cut -c "$2"
}

hamming_distance() {
  local a="$1" b="$2" i=1 d=0
  local n=${#a}
  [ "$n" -eq "${#b}" ] || { printf '99'; return 0; }
  while [ "$i" -le "$n" ]; do
    [ "$(char_at "$a" "$i")" = "$(char_at "$b" "$i")" ] || d=$((d + 1))
    i=$((i + 1))
  done
  printf '%s' "$d"
}

# True when $1 is $2 with a single extra character, or vice versa.
one_insertion_away() {
  local short="$1" long="$2"
  if [ ${#short} -gt ${#long} ]; then
    short="$2"
    long="$1"
  fi
  [ $((${#long} - ${#short})) -eq 1 ] || return 1
  local i=0 j=0 skipped=0 ls=${#short} ll=${#long} cs cl
  while [ "$j" -lt "$ll" ]; do
    if [ "$i" -lt "$ls" ]; then
      cs="$(char_at "$short" $((i + 1)))"
      cl="$(char_at "$long" $((j + 1)))"
      if [ "$cs" = "$cl" ]; then
        i=$((i + 1))
        j=$((j + 1))
        continue
      fi
    fi
    skipped=$((skipped + 1))
    [ "$skipped" -gt 1 ] && return 1
    j=$((j + 1))
  done
  [ "$i" -eq "$ls" ] && [ "$skipped" -eq 1 ]
}

# Prints the unique catalog id that $1 is a typo/prefix of, or empty.
suggest_known_dep() {
  local input="$1"
  local cand hits="" n_hits=0
  [ -z "$input" ] && return 0
  [ "$input" = "none" ] && return 0

  while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    if [ "$input" = "$cand" ]; then
      printf '%s' "$cand"
      return 0
    fi
  done <<EOF
$(catalog_ids)
EOF

  while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    case "$cand" in
      "$input"*)
        hits="${hits}${cand} "
        n_hits=$((n_hits + 1))
        ;;
    esac
  done <<EOF
$(catalog_ids)
EOF
  if [ "$n_hits" -eq 1 ] && [ ${#input} -ge 4 ]; then
    printf '%s' "$(trim "$hits")"
    return 0
  fi

  hits=""
  n_hits=0
  while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    if [ ${#input} -eq ${#cand} ]; then
      if [ "$(hamming_distance "$input" "$cand")" -le 1 ]; then
        hits="${hits}${cand} "
        n_hits=$((n_hits + 1))
      fi
    elif one_insertion_away "$input" "$cand"; then
      hits="${hits}${cand} "
      n_hits=$((n_hits + 1))
    fi
  done <<EOF
$(catalog_ids)
EOF
  if [ "$n_hits" -eq 1 ]; then
    printf '%s' "$(trim "$hits")"
  fi
}

custom_dep_exists() {
  local group="$1" artifact="$2" rec g a
  while IFS= read -r rec; do
    [ -z "$rec" ] && continue
    g="$(printf '%s' "$rec" | cut -f1)"
    a="$(printf '%s' "$rec" | cut -f2)"
    if [ "$g" = "$group" ] && [ "$a" = "$artifact" ]; then
      return 0
    fi
  done <<EOF
${CUSTOM_DEPS}
EOF
  return 1
}

append_custom_dep() {
  local group="$1" artifact="$2" version="${3-}" scope="${4-compile}"
  [ -z "$scope" ] && scope="compile"
  if custom_dep_exists "$group" "$artifact"; then
    return 0
  fi
  CUSTOM_DEPS="${CUSTOM_DEPS}${group}	${artifact}	${version}	${scope}
"
}

normalize_scope() {
  case "$(lower "$1")" in
    ""|compile|implementation|api) printf 'compile' ;;
    test|testimplementation) printf 'test' ;;
    runtime|runtimeonly) printf 'runtime' ;;
    provided|compileonly) printf 'provided' ;;
    *)
      die "unknown dependency scope '$1' (use compile, runtime, provided, or test)"
      ;;
  esac
}

# Adds an explicit group:artifact[:version[:scope]] coordinate.
add_custom_coordinate() {
  local spec="$1"
  local nf group artifact version="" scope="compile"
  nf="$(printf '%s' "$spec" | awk -F: '{print NF}')"
  group="$(printf '%s' "$spec" | awk -F: '{print $1}')"
  artifact="$(printf '%s' "$spec" | awk -F: '{print $2}')"
  case "$nf" in
    2) ;;
    3)
      version="$(printf '%s' "$spec" | awk -F: '{print $3}')"
      ;;
    4)
      version="$(printf '%s' "$spec" | awk -F: '{print $3}')"
      scope="$(normalize_scope "$(printf '%s' "$spec" | awk -F: '{print $4}')")"
      ;;
    *)
      die "malformed Maven coordinate '$spec' (expected group:artifact[:version[:scope]])"
      ;;
  esac
  is_coord_part "$group" || die "invalid groupId in '$spec'"
  is_coord_part "$artifact" || die "invalid artifactId in '$spec'"
  if [ -n "$version" ] && ! echo "$version" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._+-]*$'; then
    die "invalid version in '$spec'"
  fi
  append_custom_dep "$group" "$artifact" "$version" "$scope"
}

guess_dropwizard_artifact() {
  local token="$1"
  case "$token" in
    dropwizard-*) printf '%s' "$token" ;;
    *) printf 'dropwizard-%s' "$token" ;;
  esac
}

handle_unknown_dep() {
  local original="$1"
  local token suggested artifact
  token="$(trim "$original")"
  [ -z "$token" ] && return 0

  case "$token" in
    *:*)
      add_custom_coordinate "$token"
      info "Custom coordinate '$token' added to the build (no sample code)."
      return 0
      ;;
  esac

  token="$(lower "$token")"
  if echo "$token" | grep -q '\.'; then
    die "unknown dependency '$original' looks like a groupId; use group:artifact[:version[:scope]] (run ${SCRIPT_NAME} --list)"
  fi
  is_coord_part "$token" || die "invalid dependency id '$original' (run ${SCRIPT_NAME} --list)"

  suggested="$(suggest_known_dep "$token")"
  if [ -n "$suggested" ]; then
    note_unknown "Unknown dependency '$original'; assuming catalog id '$suggested'."
    append_dep "$suggested"
    return 0
  fi

  artifact="$(guess_dropwizard_artifact "$token")"
  append_custom_dep "io.dropwizard" "$artifact" "" "compile"
  note_unknown "Unknown dependency '$original'; adding io.dropwizard:${artifact} (pass group:artifact:version to override). No sample code will be generated."
}

resolve_dep_id() {
  local raw
  raw="$(lower "$(trim "$1")")"
  case "$raw" in
    ""|none|core|web) printf '' ;;
    jpa|data-jpa|orm|hibernate) printf 'hibernate' ;;
    jdbc|jdbi|jdbi3) printf 'jdbi3' ;;
    liquibase|flyway|migrations) printf 'migrations' ;;
    security|auth) printf 'auth' ;;
    postgres|postgresql) printf 'postgresql' ;;
    mysql|mariadb) printf 'mysql' ;;
    h2) printf 'h2' ;;
    mustache|views-mustache) printf 'views-mustache' ;;
    freemarker|views-freemarker|views) printf 'views-freemarker' ;;
    test|testing) printf 'testing' ;;
    client|httpclient|jersey-client) printf 'client' ;;
    forms|multipart) printf 'forms' ;;
    assets|static) printf 'assets' ;;
    json-logging|jsonlog) printf 'json-logging' ;;
    http2|h2c) printf 'http2' ;;
    graphite|metrics-graphite) printf 'metrics-graphite' ;;
    docker) printf 'docker' ;;
    testing|auth|hibernate|jdbi3|migrations|client|forms|assets|http2|json-logging|metrics-graphite|h2|postgresql|mysql|views-freemarker|views-mustache)
      printf '%s' "$raw"
      ;;
    *)
      printf ''
      return 1
      ;;
  esac
}

normalize_deps() {
  local original="$1"
  local item resolved skip_testing="false"
  DEPS=""
  CUSTOM_DEPS=""
  UNKNOWN_NOTES=""
  if [ -z "$original" ]; then
    original="$DEFAULT_DEPS"
  fi
  original="$(printf '%s' "$original" | tr ',' ' ')"
  local IFS=' '
  # shellcheck disable=SC2086
  set -- $original
  for item in "$@"; do
    item="$(trim "$item")"
    [ -z "$item" ] && continue
    case "$(lower "$item")" in
      none)
        skip_testing="true"
        continue
        ;;
      no-testing)
        skip_testing="true"
        continue
        ;;
      core|web)
        continue
        ;;
    esac
    resolved="$(resolve_dep_id "$item" || true)"
    if [ -n "$resolved" ]; then
      append_dep "$resolved"
    else
      handle_unknown_dep "$item"
    fi
  done
  if [ "$skip_testing" != true ]; then
    append_dep testing
  fi
  if has_dep docker; then
    DOCKER="true"
  fi
  if needs_database && ! has_dep h2 && ! has_dep postgresql && ! has_dep mysql; then
    append_dep h2
  fi
}

needs_database() {
  has_dep hibernate || has_dep jdbi3 || has_dep migrations
}

dep_label() {
  case "$1" in
    testing) printf 'JUnit 5 test helpers (ResourceExtension, DropwizardAppExtension)' ;;
    auth) printf 'HTTP basic auth (Authenticator, Authorizer, @Auth)' ;;
    hibernate) printf 'Hibernate ORM, SessionFactory, @UnitOfWork DAOs' ;;
    jdbi3) printf 'JDBI 3 SQL objects and DBI factory' ;;
    migrations) printf 'Liquibase migrations bundle (db migrate command)' ;;
    client) printf 'Instrumented Jersey/HTTP client' ;;
    forms) printf 'Multipart form data (file uploads)' ;;
    views-freemarker) printf 'HTML views rendered with FreeMarker' ;;
    views-mustache) printf 'HTML views rendered with Mustache' ;;
    assets) printf 'Classpath static assets served under /static' ;;
    json-logging) printf 'JSON log layout for production log shipping' ;;
    http2) printf 'HTTP/2 connector support (h2 / h2c)' ;;
    metrics-graphite) printf 'Graphite metrics reporter' ;;
    h2) printf 'H2 embedded JDBC driver' ;;
    postgresql) printf 'PostgreSQL JDBC driver' ;;
    mysql) printf 'MySQL JDBC driver' ;;
    docker) printf 'Dockerfile for the shaded application jar' ;;
    *) printf '%s' "$1" ;;
  esac
}

list_dependencies() {
  cat <<EOF
${C_BOLD}Available dependencies${C_RESET}  (core is always included)

  ${C_BOLD}Web${C_RESET}
    testing              $(dep_label testing)
    auth                 $(dep_label auth)
    client               $(dep_label client)
    forms                $(dep_label forms)
    assets               $(dep_label assets)
    views-freemarker     $(dep_label views-freemarker)
    views-mustache       $(dep_label views-mustache)
    http2                $(dep_label http2)

  ${C_BOLD}Data${C_RESET}
    hibernate            $(dep_label hibernate)
    jdbi3                $(dep_label jdbi3)
    migrations           $(dep_label migrations)
    h2                   $(dep_label h2)
    postgresql           $(dep_label postgresql)
    mysql                $(dep_label mysql)

  ${C_BOLD}Ops${C_RESET}
    json-logging         $(dep_label json-logging)
    metrics-graphite     $(dep_label metrics-graphite)
    docker               $(dep_label docker)

Aliases: jpa→hibernate, jdbc→jdbi3, liquibase→migrations, security→auth,
         postgres→postgresql, views→views-freemarker

  ${C_BOLD}Unknown / custom${C_RESET}
    group:artifact[:version[:scope]]   e.g. com.google.guava:guava:33.4.8-jre
    dropwizard-kafka                   io.dropwizard:dropwizard-kafka (BOM version)
    redis                              io.dropwizard:dropwizard-redis
    Catalog typos are auto-corrected (hibernat → hibernate). Custom coordinates
    are added to the build file only; no sample classes are generated.
EOF
}

prompt() {
  # prompt VAR "label" "default"
  local __var="$1"
  local __label="$2"
  local __default="${3-}"
  local __input=""
  if [ -n "$__default" ]; then
    printf '%s%s%s %s[%s]%s: ' "${C_BOLD}" "$__label" "${C_RESET}" "${C_DIM}" "$__default" "${C_RESET}" > /dev/tty
  else
    printf '%s%s%s: ' "${C_BOLD}" "$__label" "${C_RESET}" > /dev/tty
  fi
  IFS= read -r __input < /dev/tty || true
  if [ -z "$__input" ]; then
    __input="$__default"
  fi
  eval "$__var=\"\$__input\""
}

confirm() {
  local answer=""
  printf '%s%s%s ' "${C_BOLD}" "$1 [Y/n]" "${C_RESET}" > /dev/tty
  IFS= read -r answer < /dev/tty || true
  answer="$(lower "$(trim "$answer")")"
  case "$answer" in
    ""|y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

major_dw() {
  printf '%s' "$DW_VERSION" | cut -d. -f1
}

min_java_for_dw() {
  case "$(major_dw)" in
    5) printf '17' ;;
    4|3) printf '11' ;;
    *) printf '17' ;;
  esac
}

validate() {
  echo "$GROUP" | grep -Eq '^[A-Za-z0-9_.-]+$' || die "invalid groupId '$GROUP'"
  echo "$ARTIFACT" | grep -Eq '^[A-Za-z0-9_.-]+$' || die "invalid artifactId '$ARTIFACT'"
  echo "$PACKAGE" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$' \
    || die "invalid package '$PACKAGE'"
  echo "$CLASS_PREFIX" | grep -Eq '^[A-Z][A-Za-z0-9]*$' \
    || die "invalid class name '$CLASS_PREFIX' (use PascalCase, e.g. HelloWorld)"
  echo "$DW_VERSION" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?([.-].*)?$' \
    || die "invalid Dropwizard version '$DW_VERSION'"
  case "$JAVA_VERSION" in
    11|17|21|25) ;;
    *) die "unsupported Java version '$JAVA_VERSION' (11, 17, 21, 25)" ;;
  esac
  case "$TYPE" in
    maven|gradle) ;;
    *) die "build must be maven or gradle (got '$TYPE')" ;;
  esac
  case "$(major_dw)" in
    5)
      if [ "$JAVA_VERSION" -lt 17 ]; then
        die "Dropwizard 5.x requires Java 17+"
      fi
      ;;
    3|4)
      if [ "$JAVA_VERSION" -lt 11 ]; then
        die "Dropwizard ${DW_VERSION} requires Java 11+"
      fi
      ;;
  esac
}

mkdir_p() {
  mkdir -p "$@"
}

write_file() {
  local path="$1"
  mkdir_p "$(dirname "$path")"
  cat > "$path"
}

jdbc_driver_class() {
  if has_dep postgresql; then
    printf 'org.postgresql.Driver'
  elif has_dep mysql; then
    printf 'com.mysql.cj.jdbc.Driver'
  else
    printf 'org.h2.Driver'
  fi
}

jdbc_url() {
  if has_dep postgresql; then
    printf 'jdbc:postgresql://localhost:5432/%s' "$ARTIFACT"
  elif has_dep mysql; then
    printf 'jdbc:mysql://localhost:3306/%s?useSSL=false&allowPublicKeyRetrieval=true' "$ARTIFACT"
  else
    printf 'jdbc:h2:./data/%s' "$ARTIFACT"
  fi
}

jdbc_user() {
  if has_dep postgresql; then
    printf 'postgres'
  elif has_dep mysql; then
    printf 'root'
  else
    printf 'sa'
  fi
}

uses_hibernate_sample() {
  has_dep hibernate
}

uses_jdbi_sample() {
  has_dep jdbi3 && ! has_dep hibernate
}

# ---------------------------------------------------------------------------
# Interactive wizard
# ---------------------------------------------------------------------------

print_banner() {
  cat <<EOF
${C_BLUE}${C_BOLD}
    ____                                    _                      _
   / __ \\_________  ____ _      __  ____ _(_)___  _________ ______/ |
  / / / / ___/ __ \\/ __ \\ | /| / / / __ \`/ / __ \\/ ___/ __ \`/ ___/ /
 / /_/ / /  / /_/ / /_/ / |/ |/ / / /_/ / / / / (__  ) /_/ / /  / /
/_____/_/   \\____/ .___/|__/|__/  \\__,_/_/_/ /_/____/\\__,_/_/  /_/
                 |_|
                    Initializr  ${C_RESET}${C_DIM}v${SCRIPT_VERSION}  ·  Dropwizard project generator${C_RESET}

EOF
}

run_wizard() {
  local build_in dw_in java_in deps_in
  print_banner
  printf '%sProject metadata%s\n' "${C_BOLD}" "${C_RESET}"
  printf '%sPress Enter to accept the value in brackets.%s\n\n' "${C_DIM}" "${C_RESET}"

  prompt build_in "Build tool (maven | gradle)" "${TYPE:-$DEFAULT_BUILD}"
  TYPE="$(lower "$(trim "$build_in")")"

  printf '\n  %sDropwizard lines:%s  5.0.x (Java 17+, current)  ·  4.0.x (Java 11+)  ·  3.0.x (Java 11+)\n' "${C_DIM}" "${C_RESET}"
  prompt dw_in "Dropwizard version" "${DW_VERSION:-$DEFAULT_DW_VERSION}"
  DW_VERSION="$(trim "$dw_in")"

  prompt java_in "Java version" "${JAVA_VERSION:-$(min_java_for_dw)}"
  JAVA_VERSION="$(trim "$java_in")"

  prompt GROUP "Group" "${GROUP:-$DEFAULT_GROUP}"
  GROUP="$(trim "$GROUP")"

  prompt ARTIFACT "Artifact" "${ARTIFACT:-$DEFAULT_ARTIFACT}"
  ARTIFACT="$(trim "$ARTIFACT")"

  prompt NAME "Name" "${NAME:-$(to_pascal "$ARTIFACT")}"
  NAME="$(trim "$NAME")"

  prompt DESCRIPTION "Description" "${DESCRIPTION:-$DEFAULT_DESCRIPTION}"

  prompt PACKAGE "Package" "${PACKAGE:-${GROUP}.$(to_artifact_suffix "$ARTIFACT")}"
  PACKAGE="$(trim "$PACKAGE")"

  printf '\n%sDependencies%s  (comma-separated ids; type %slist%s for the catalog)\n' "${C_BOLD}" "${C_RESET}" "${C_CYAN}" "${C_RESET}"
  list_dependencies
  printf '\n'
  while true; do
    prompt deps_in "Dependencies" "${DEPS:-$DEFAULT_DEPS}"
    deps_in="$(trim "$deps_in")"
    case "$(lower "$deps_in")" in
      list|ls|help)
        printf '\n'
        list_dependencies
        printf '\n'
        continue
        ;;
    esac
    DEPS=""
    normalize_deps "$deps_in"
    break
  done

  prompt OUTPUT "Output directory" "${OUTPUT:-./$ARTIFACT}"
  OUTPUT="$(trim "$OUTPUT")"

  printf '\n'
  if confirm "Include a Dockerfile?"; then
    DOCKER="true"
  fi
  if confirm "Initialize a git repository?"; then
    GIT_INIT="true"
  fi
}

# ---------------------------------------------------------------------------
# Generated files
# ---------------------------------------------------------------------------

generate_gitignore() {
  write_file "$PROJECT_DIR/.gitignore" <<'EOF'
# Build
target/
build/
out/
.gradle/
dependency-reduced-pom.xml
*.jar
!gradle/wrapper/gradle-wrapper.jar

# IDE
.idea/
*.iml
*.ipr
*.iws
.project
.classpath
.settings/
.vscode/
*.swp
.DS_Store

# Runtime
*.log
data/
.attach_pid*
EOF
}

generate_banner() {
  write_file "$PROJECT_DIR/src/main/resources/banner.txt" <<EOF
     ${NAME}
     ${DESCRIPTION}
EOF
}

pom_dep() {
  local artifact="$1"
  local scope="${2-}"
  if [ -n "$scope" ]; then
    cat <<EOF
        <dependency>
            <groupId>io.dropwizard</groupId>
            <artifactId>${artifact}</artifactId>
            <scope>${scope}</scope>
        </dependency>
EOF
  else
    cat <<EOF
        <dependency>
            <groupId>io.dropwizard</groupId>
            <artifactId>${artifact}</artifactId>
        </dependency>
EOF
  fi
}

external_dep() {
  cat <<EOF
        <dependency>
            <groupId>$1</groupId>
            <artifactId>$2</artifactId>
            <version>$3</version>
        </dependency>
EOF
}

pom_custom_deps() {
  local rec group artifact version scope
  while IFS= read -r rec; do
    [ -z "$rec" ] && continue
    group="$(printf '%s' "$rec" | cut -f1)"
    artifact="$(printf '%s' "$rec" | cut -f2)"
    version="$(printf '%s' "$rec" | cut -f3)"
    scope="$(printf '%s' "$rec" | cut -f4)"
    printf '        <dependency>\n'
    printf '            <groupId>%s</groupId>\n' "$group"
    printf '            <artifactId>%s</artifactId>\n' "$artifact"
    [ -n "$version" ] && printf '            <version>%s</version>\n' "$version"
    if [ -n "$scope" ] && [ "$scope" != compile ]; then
      printf '            <scope>%s</scope>\n' "$scope"
    fi
    printf '        </dependency>\n'
  done <<EOF
${CUSTOM_DEPS}
EOF
}

gradle_custom_deps() {
  local rec group artifact version scope conf coord
  while IFS= read -r rec; do
    [ -z "$rec" ] && continue
    group="$(printf '%s' "$rec" | cut -f1)"
    artifact="$(printf '%s' "$rec" | cut -f2)"
    version="$(printf '%s' "$rec" | cut -f3)"
    scope="$(printf '%s' "$rec" | cut -f4)"
    case "$scope" in
      test) conf="testImplementation" ;;
      runtime) conf="runtimeOnly" ;;
      provided) conf="compileOnly" ;;
      *) conf="implementation" ;;
    esac
    if [ -n "$version" ]; then
      coord="${group}:${artifact}:${version}"
    else
      coord="${group}:${artifact}"
    fi
    printf '    %s "%s"\n' "$conf" "$coord"
  done <<EOF
${CUSTOM_DEPS}
EOF
}

generate_pom() {
  local deps=""
  deps="$(pom_dep dropwizard-core)"
  has_dep testing && deps="${deps}
$(pom_dep dropwizard-testing test)"
  has_dep auth && deps="${deps}
$(pom_dep dropwizard-auth)"
  has_dep hibernate && deps="${deps}
$(pom_dep dropwizard-hibernate)"
  has_dep jdbi3 && deps="${deps}
$(pom_dep dropwizard-jdbi3)"
  has_dep migrations && deps="${deps}
$(pom_dep dropwizard-migrations)"
  has_dep client && deps="${deps}
$(pom_dep dropwizard-client)"
  has_dep forms && deps="${deps}
$(pom_dep dropwizard-forms)"
  has_dep views-freemarker && deps="${deps}
$(pom_dep dropwizard-views-freemarker)"
  has_dep views-mustache && deps="${deps}
$(pom_dep dropwizard-views-mustache)"
  has_dep assets && deps="${deps}
$(pom_dep dropwizard-assets)"
  has_dep json-logging && deps="${deps}
$(pom_dep dropwizard-json-logging)"
  has_dep http2 && deps="${deps}
$(pom_dep dropwizard-http2)"
  has_dep metrics-graphite && deps="${deps}
$(pom_dep dropwizard-metrics-graphite)"
  has_dep h2 && deps="${deps}
$(external_dep com.h2database h2 "$H2_VERSION")"
  has_dep postgresql && deps="${deps}
$(external_dep org.postgresql postgresql "$POSTGRES_VERSION")"
  has_dep mysql && deps="${deps}
$(external_dep com.mysql mysql-connector-j "$MYSQL_VERSION")"
  if [ -n "$(trim "$CUSTOM_DEPS")" ]; then
    deps="${deps}
$(pom_custom_deps)"
  fi
  deps="${deps}
        <dependency>
            <groupId>org.assertj</groupId>
            <artifactId>assertj-core</artifactId>
            <version>${ASSERTJ_VERSION}</version>
            <scope>test</scope>
        </dependency>"

  write_file "$PROJECT_DIR/pom.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>${GROUP}</groupId>
    <artifactId>${ARTIFACT}</artifactId>
    <version>1.0.0-SNAPSHOT</version>
    <packaging>jar</packaging>

    <name>${NAME}</name>
    <description>${DESCRIPTION}</description>

    <properties>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
        <project.reporting.outputEncoding>UTF-8</project.reporting.outputEncoding>
        <maven.compiler.release>${JAVA_VERSION}</maven.compiler.release>
        <dropwizard.version>${DW_VERSION}</dropwizard.version>
        <mainClass>${PACKAGE}.${CLASS_PREFIX}Application</mainClass>
    </properties>

    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>io.dropwizard</groupId>
                <artifactId>dropwizard-bom</artifactId>
                <version>\${dropwizard.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
        </dependencies>
    </dependencyManagement>

    <dependencies>
${deps}
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <version>${MAVEN_COMPILER_PLUGIN}</version>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-surefire-plugin</artifactId>
                <version>${MAVEN_SUREFIRE_PLUGIN}</version>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-jar-plugin</artifactId>
                <version>${MAVEN_JAR_PLUGIN}</version>
                <configuration>
                    <archive>
                        <manifest>
                            <addDefaultImplementationEntries>true</addDefaultImplementationEntries>
                            <addClasspath>true</addClasspath>
                            <mainClass>\${mainClass}</mainClass>
                        </manifest>
                    </archive>
                </configuration>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-shade-plugin</artifactId>
                <version>${MAVEN_SHADE_PLUGIN}</version>
                <configuration>
                    <createDependencyReducedPom>true</createDependencyReducedPom>
                    <filters>
                        <filter>
                            <artifact>*:*</artifact>
                            <excludes>
                                <exclude>META-INF/*.SF</exclude>
                                <exclude>META-INF/*.DSA</exclude>
                                <exclude>META-INF/*.RSA</exclude>
                            </excludes>
                        </filter>
                    </filters>
                </configuration>
                <executions>
                    <execution>
                        <phase>package</phase>
                        <goals>
                            <goal>shade</goal>
                        </goals>
                        <configuration>
                            <transformers>
                                <transformer implementation="org.apache.maven.plugins.shade.resource.ServicesResourceTransformer"/>
                                <transformer implementation="org.apache.maven.plugins.shade.resource.ManifestResourceTransformer">
                                    <mainClass>\${mainClass}</mainClass>
                                </transformer>
                            </transformers>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
</project>
EOF
}

generate_gradle() {
  local deps=""
  deps="${deps}    implementation \"io.dropwizard:dropwizard-core\"
"
  has_dep auth && deps="${deps}    implementation \"io.dropwizard:dropwizard-auth\"
"
  has_dep hibernate && deps="${deps}    implementation \"io.dropwizard:dropwizard-hibernate\"
"
  has_dep jdbi3 && deps="${deps}    implementation \"io.dropwizard:dropwizard-jdbi3\"
"
  has_dep migrations && deps="${deps}    implementation \"io.dropwizard:dropwizard-migrations\"
"
  has_dep client && deps="${deps}    implementation \"io.dropwizard:dropwizard-client\"
"
  has_dep forms && deps="${deps}    implementation \"io.dropwizard:dropwizard-forms\"
"
  has_dep views-freemarker && deps="${deps}    implementation \"io.dropwizard:dropwizard-views-freemarker\"
"
  has_dep views-mustache && deps="${deps}    implementation \"io.dropwizard:dropwizard-views-mustache\"
"
  has_dep assets && deps="${deps}    implementation \"io.dropwizard:dropwizard-assets\"
"
  has_dep json-logging && deps="${deps}    implementation \"io.dropwizard:dropwizard-json-logging\"
"
  has_dep http2 && deps="${deps}    implementation \"io.dropwizard:dropwizard-http2\"
"
  has_dep metrics-graphite && deps="${deps}    implementation \"io.dropwizard:dropwizard-metrics-graphite\"
"
  has_dep h2 && deps="${deps}    implementation \"com.h2database:h2:${H2_VERSION}\"
"
  has_dep postgresql && deps="${deps}    implementation \"org.postgresql:postgresql:${POSTGRES_VERSION}\"
"
  has_dep mysql && deps="${deps}    implementation \"com.mysql:mysql-connector-j:${MYSQL_VERSION}\"
"
  if [ -n "$(trim "$CUSTOM_DEPS")" ]; then
    deps="${deps}$(gradle_custom_deps)
"
  fi
  has_dep testing && deps="${deps}    testImplementation \"io.dropwizard:dropwizard-testing\"
"
  deps="${deps}    testImplementation \"org.junit.jupiter:junit-jupiter:${JUNIT_JUPITER_VERSION}\"
    testRuntimeOnly \"org.junit.platform:junit-platform-launcher:${JUNIT_PLATFORM_VERSION}\"
    testImplementation \"org.assertj:assertj-core:${ASSERTJ_VERSION}\"
"

  write_file "$PROJECT_DIR/settings.gradle" <<EOF
rootProject.name = '${ARTIFACT}'
EOF

  write_file "$PROJECT_DIR/gradle.properties" <<EOF
org.gradle.jvmargs=-Xmx512m -Dfile.encoding=UTF-8
org.gradle.parallel=true
EOF

  write_file "$PROJECT_DIR/build.gradle" <<EOF
plugins {
    id 'java'
    id 'application'
    id 'com.gradleup.shadow' version '${SHADOW_PLUGIN}'
}

group = '${GROUP}'
version = '1.0.0-SNAPSHOT'

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(${JAVA_VERSION})
    }
}

repositories {
    mavenCentral()
}

dependencies {
    implementation platform("io.dropwizard:dropwizard-bom:${DW_VERSION}")
${deps}}

application {
    mainClass = '${PACKAGE}.${CLASS_PREFIX}Application'
}

tasks.named('run') {
    args = ['server', 'config.yml']
}

shadowJar {
    archiveClassifier.set('')
    mergeServiceFiles()
    manifest {
        attributes 'Main-Class': '${PACKAGE}.${CLASS_PREFIX}Application'
        attributes 'Implementation-Title': '${NAME}'
        attributes 'Implementation-Version': project.version
    }
}

tasks.named('jar') {
    enabled = false
}

tasks.named('build') {
    dependsOn tasks.named('shadowJar')
}

tasks.withType(JavaCompile).configureEach {
    options.encoding = 'UTF-8'
    options.release = ${JAVA_VERSION}
}

test {
    useJUnitPlatform()
}
EOF
}

generate_config_yml() {
  local db_block=""
  local client_block=""
  local views_block=""
  local metrics_block=""
  local logging_appender=""
  local http2_comment=""

  if needs_database; then
    db_block="$(cat <<EOF

database:
  driverClass: $(jdbc_driver_class)
  user: $(jdbc_user)
  password: ""
  url: $(jdbc_url)
  properties:
    charSet: UTF-8
  maxWaitForConnection: 1s
  validationQuery: "SELECT 1"
  minSize: 1
  maxSize: 8
  checkConnectionWhileIdle: false
  evictionInterval: 10s
  minIdleTime: 1 minute
EOF
)"
  fi

  if has_dep client; then
    client_block="$(cat <<'EOF'

httpClient:
  timeout: 5s
  connectionTimeout: 2s
  retries: 0
EOF
)"
  fi

  if has_dep views-freemarker || has_dep views-mustache; then
    views_block="$(cat <<'EOF'

viewRendererConfiguration:
  freemarker:
    strict_syntax: true
    whitespace_stripping: true
  mustache:
    cache: false
EOF
)"
  fi

  if has_dep metrics-graphite; then
    metrics_block="$(cat <<EOF

metrics:
  frequency: 1 minute
  reporters:
    - type: graphite
      host: localhost
      port: 2003
      prefix: ${ARTIFACT}
      frequency: 1 minute
EOF
)"
  fi

  if has_dep json-logging; then
    logging_appender="$(cat <<'EOF'
    - type: console
      layout:
        type: json
EOF
)"
  else
    logging_appender="$(cat <<'EOF'
    - type: console
      timeZone: UTC
      logFormat: "%-5level [%d{ISO8601,UTC}] [%thread] %logger{36} - %msg%n"
EOF
)"
  fi

  if has_dep http2; then
    http2_comment="$(cat <<'EOF'
  # HTTP/2 cleartext example (requires dropwizard-http2):
  # applicationConnectors:
  #   - type: h2c
  #     port: 8080
EOF
)"
  fi

  write_file "$PROJECT_DIR/config.yml" <<EOF
---
template: ${DW_TEMPLATE:-Hello, %s!}
defaultName: \${DW_DEFAULT_NAME:-Stranger}
${db_block}${client_block}${views_block}${metrics_block}
server:
  applicationConnectors:
    - type: http
      port: 8080
  adminConnectors:
    - type: http
      port: 8081
${http2_comment}
logging:
  level: INFO
  loggers:
    ${PACKAGE}: DEBUG
  appenders:
${logging_appender}
EOF
}

generate_configuration_java() {
  local extras_fields=""
  local extras_methods=""
  local extras_imports=""

  extras_imports="$(cat <<EOF
import com.fasterxml.jackson.annotation.JsonProperty;
import io.dropwizard.core.Configuration;
import jakarta.validation.constraints.NotEmpty;
EOF
)"

  if needs_database; then
    extras_imports="${extras_imports}
import io.dropwizard.db.DataSourceFactory;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;"
    extras_fields="${extras_fields}
    @Valid
    @NotNull
    private DataSourceFactory database = new DataSourceFactory();
"
    extras_methods="${extras_methods}
    @JsonProperty(\"database\")
    public DataSourceFactory getDataSourceFactory() {
        return database;
    }

    @JsonProperty(\"database\")
    public void setDataSourceFactory(DataSourceFactory database) {
        this.database = database;
    }
"
  fi

  if has_dep client; then
    extras_imports="${extras_imports}
import io.dropwizard.client.JerseyClientConfiguration;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;"
    extras_fields="${extras_fields}
    @Valid
    @NotNull
    private JerseyClientConfiguration httpClient = new JerseyClientConfiguration();
"
    extras_methods="${extras_methods}
    @JsonProperty(\"httpClient\")
    public JerseyClientConfiguration getHttpClient() {
        return httpClient;
    }

    @JsonProperty(\"httpClient\")
    public void setHttpClient(JerseyClientConfiguration httpClient) {
        this.httpClient = httpClient;
    }
"
  fi

  if has_dep views-freemarker || has_dep views-mustache; then
    extras_imports="${extras_imports}
import java.util.Collections;
import java.util.Map;"
    extras_fields="${extras_fields}
    private Map<String, Map<String, String>> viewRendererConfiguration = Collections.emptyMap();
"
    extras_methods="${extras_methods}
    @JsonProperty(\"viewRendererConfiguration\")
    public Map<String, Map<String, String>> getViewRendererConfiguration() {
        return viewRendererConfiguration;
    }

    @JsonProperty(\"viewRendererConfiguration\")
    public void setViewRendererConfiguration(Map<String, Map<String, String>> viewRendererConfiguration) {
        this.viewRendererConfiguration = viewRendererConfiguration;
    }
"
  fi

  write_file "$SRC_MAIN/${CLASS_PREFIX}Configuration.java" <<EOF
package ${PACKAGE};

${extras_imports}

public class ${CLASS_PREFIX}Configuration extends Configuration {
    @NotEmpty
    private String template;

    @NotEmpty
    private String defaultName = "Stranger";
${extras_fields}
    @JsonProperty
    public String getTemplate() {
        return template;
    }

    @JsonProperty
    public void setTemplate(String template) {
        this.template = template;
    }

    @JsonProperty
    public String getDefaultName() {
        return defaultName;
    }

    @JsonProperty
    public void setDefaultName(String defaultName) {
        this.defaultName = defaultName;
    }
${extras_methods}}
EOF
}

generate_application_java() {
  local imports init_body run_body fields=""
  imports="$(cat <<EOF
import ${PACKAGE}.health.TemplateHealthCheck;
import ${PACKAGE}.resources.HelloWorldResource;
import io.dropwizard.configuration.EnvironmentVariableSubstitutor;
import io.dropwizard.configuration.SubstitutingSourceProvider;
import io.dropwizard.core.Application;
import io.dropwizard.core.setup.Bootstrap;
import io.dropwizard.core.setup.Environment;
EOF
)"

  init_body="$(cat <<'EOF'
        bootstrap.setConfigurationSourceProvider(
                new SubstitutingSourceProvider(
                        bootstrap.getConfigurationSourceProvider(),
                        new EnvironmentVariableSubstitutor(false)
                )
        );
EOF
)"

  run_body="$(cat <<EOF
        final HelloWorldResource resource = new HelloWorldResource(
                configuration.getTemplate(),
                configuration.getDefaultName()
        );
        environment.jersey().register(resource);
        environment.healthChecks().register(
                "template",
                new TemplateHealthCheck(configuration.getTemplate())
        );
EOF
)"

  if has_dep assets; then
    imports="${imports}
import io.dropwizard.assets.AssetsBundle;"
    init_body="${init_body}
        bootstrap.addBundle(new AssetsBundle(\"/assets/\", \"/static/\", \"index.html\"));"
  fi

  if has_dep forms; then
    imports="${imports}
import io.dropwizard.forms.MultiPartBundle;"
    init_body="${init_body}
        bootstrap.addBundle(new MultiPartBundle());"
  fi

  if has_dep views-freemarker || has_dep views-mustache; then
    imports="${imports}
import ${PACKAGE}.resources.ViewResource;
import io.dropwizard.views.common.ViewBundle;
import java.util.Map;"
    init_body="${init_body}
        bootstrap.addBundle(new ViewBundle<${CLASS_PREFIX}Configuration>() {
            @Override
            public Map<String, Map<String, String>> getViewConfiguration(${CLASS_PREFIX}Configuration configuration) {
                return configuration.getViewRendererConfiguration();
            }
        });"
    run_body="${run_body}
        environment.jersey().register(new ViewResource(configuration.getDefaultName()));"
  fi

  if has_dep migrations; then
    imports="${imports}
import io.dropwizard.db.DataSourceFactory;
import io.dropwizard.migrations.MigrationsBundle;"
    init_body="${init_body}
        bootstrap.addBundle(new MigrationsBundle<${CLASS_PREFIX}Configuration>() {
            @Override
            public DataSourceFactory getDataSourceFactory(${CLASS_PREFIX}Configuration configuration) {
                return configuration.getDataSourceFactory();
            }
        });"
  fi

  if has_dep hibernate; then
    imports="${imports}
import ${PACKAGE}.core.Person;
import ${PACKAGE}.db.PersonDAO;
import ${PACKAGE}.resources.PeopleResource;
import ${PACKAGE}.resources.PersonResource;
import io.dropwizard.db.DataSourceFactory;
import io.dropwizard.hibernate.HibernateBundle;"
    fields="${fields}
    private final HibernateBundle<${CLASS_PREFIX}Configuration> hibernateBundle =
            new HibernateBundle<${CLASS_PREFIX}Configuration>(Person.class) {
                @Override
                public DataSourceFactory getDataSourceFactory(${CLASS_PREFIX}Configuration configuration) {
                    return configuration.getDataSourceFactory();
                }
            };
"
    init_body="${init_body}
        bootstrap.addBundle(hibernateBundle);"
    run_body="${run_body}
        final PersonDAO dao = new PersonDAO(hibernateBundle.getSessionFactory());
        environment.jersey().register(new PeopleResource(dao));
        environment.jersey().register(new PersonResource(dao));"
  elif has_dep jdbi3; then
    imports="${imports}
import ${PACKAGE}.db.PersonDAO;
import ${PACKAGE}.resources.PeopleResource;
import ${PACKAGE}.resources.PersonResource;
import io.dropwizard.jdbi3.JdbiFactory;
import org.jdbi.v3.core.Jdbi;"
    run_body="${run_body}
        final JdbiFactory factory = new JdbiFactory();
        final Jdbi jdbi = factory.build(environment, configuration.getDataSourceFactory(), \"sql\");
        final PersonDAO dao = jdbi.onDemand(PersonDAO.class);
        environment.jersey().register(new PeopleResource(dao));
        environment.jersey().register(new PersonResource(dao));"
  fi

  if has_dep auth; then
    imports="${imports}
import ${PACKAGE}.auth.ExampleAuthenticator;
import ${PACKAGE}.auth.ExampleAuthorizer;
import ${PACKAGE}.auth.User;
import ${PACKAGE}.resources.ProtectedResource;
import io.dropwizard.auth.AuthDynamicFeature;
import io.dropwizard.auth.AuthValueFactoryProvider;
import io.dropwizard.auth.basic.BasicCredentialAuthFilter;
import org.glassfish.jersey.server.filter.RolesAllowedDynamicFeature;"
    run_body="${run_body}
        environment.jersey().register(new AuthDynamicFeature(
                new BasicCredentialAuthFilter.Builder<User>()
                        .setAuthenticator(new ExampleAuthenticator())
                        .setAuthorizer(new ExampleAuthorizer())
                        .setRealm(\"${NAME}\")
                        .buildAuthFilter()));
        environment.jersey().register(new AuthValueFactoryProvider.Binder<>(User.class));
        environment.jersey().register(RolesAllowedDynamicFeature.class);
        environment.jersey().register(new ProtectedResource());"
  fi

  if has_dep client; then
    imports="${imports}
import io.dropwizard.client.JerseyClientBuilder;
import jakarta.ws.rs.client.Client;"
    run_body="${run_body}
        final Client httpClient = new JerseyClientBuilder(environment)
                .using(configuration.getHttpClient())
                .build(getName());
        environment.jersey().property(\"httpClient\", httpClient);"
  fi

  write_file "$SRC_MAIN/${CLASS_PREFIX}Application.java" <<EOF
package ${PACKAGE};

${imports}

public class ${CLASS_PREFIX}Application extends Application<${CLASS_PREFIX}Configuration> {
${fields}
    public static void main(String[] args) throws Exception {
        new ${CLASS_PREFIX}Application().run(args);
    }

    @Override
    public String getName() {
        return "${ARTIFACT}";
    }

    @Override
    public void initialize(Bootstrap<${CLASS_PREFIX}Configuration> bootstrap) {
${init_body}
    }

    @Override
    public void run(${CLASS_PREFIX}Configuration configuration, Environment environment) {
${run_body}
    }
}
EOF
}

generate_core_java() {
  write_file "$SRC_MAIN/api/Saying.java" <<EOF
package ${PACKAGE}.api;

import com.fasterxml.jackson.annotation.JsonProperty;

public class Saying {
    private long id;
    private String content;

    public Saying() {
        // Jackson deserialization
    }

    public Saying(long id, String content) {
        this.id = id;
        this.content = content;
    }

    @JsonProperty
    public long getId() {
        return id;
    }

    @JsonProperty
    public String getContent() {
        return content;
    }
}
EOF

  write_file "$SRC_MAIN/resources/HelloWorldResource.java" <<EOF
package ${PACKAGE}.resources;

import ${PACKAGE}.api.Saying;
import com.codahale.metrics.annotation.Timed;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;

import java.util.Optional;
import java.util.concurrent.atomic.AtomicLong;

@Path("/hello-world")
@Produces(MediaType.APPLICATION_JSON)
public class HelloWorldResource {
    private final String template;
    private final String defaultName;
    private final AtomicLong counter;

    public HelloWorldResource(String template, String defaultName) {
        this.template = template;
        this.defaultName = defaultName;
        this.counter = new AtomicLong();
    }

    @GET
    @Timed
    public Saying sayHello(@QueryParam("name") Optional<String> name) {
        final String value = String.format(template, name.orElse(defaultName));
        return new Saying(counter.incrementAndGet(), value);
    }
}
EOF

  write_file "$SRC_MAIN/health/TemplateHealthCheck.java" <<EOF
package ${PACKAGE}.health;

import com.codahale.metrics.health.HealthCheck;

public class TemplateHealthCheck extends HealthCheck {
    private final String template;

    public TemplateHealthCheck(String template) {
        this.template = template;
    }

    @Override
    protected Result check() throws Exception {
        final String saying = String.format(template, "TEST");
        if (!saying.contains("TEST")) {
            return Result.unhealthy("template doesn't include a name");
        }
        return Result.healthy();
    }
}
EOF
}

generate_person_hibernate() {
  write_file "$SRC_MAIN/core/Person.java" <<EOF
package ${PACKAGE}.core;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.NamedQuery;
import jakarta.persistence.Table;
import jakarta.validation.constraints.NotEmpty;

@Entity
@Table(name = "people")
@NamedQuery(
        name = "${PACKAGE}.core.Person.findAll",
        query = "SELECT p FROM Person p"
)
public class Person {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private long id;

    @NotEmpty
    @Column(name = "full_name", nullable = false)
    private String fullName;

    @Column(name = "job_title")
    private String jobTitle;

    public Person() {
        // JPA
    }

    public Person(String fullName, String jobTitle) {
        this.fullName = fullName;
        this.jobTitle = jobTitle;
    }

    public long getId() {
        return id;
    }

    public String getFullName() {
        return fullName;
    }

    public void setFullName(String fullName) {
        this.fullName = fullName;
    }

    public String getJobTitle() {
        return jobTitle;
    }

    public void setJobTitle(String jobTitle) {
        this.jobTitle = jobTitle;
    }
}
EOF

  write_file "$SRC_MAIN/db/PersonDAO.java" <<EOF
package ${PACKAGE}.db;

import ${PACKAGE}.core.Person;
import io.dropwizard.hibernate.AbstractDAO;
import org.hibernate.SessionFactory;

import java.util.List;
import java.util.Optional;

public class PersonDAO extends AbstractDAO<Person> {
    public PersonDAO(SessionFactory sessionFactory) {
        super(sessionFactory);
    }

    public Optional<Person> findById(long id) {
        return Optional.ofNullable(get(id));
    }

    public Person create(Person person) {
        return persist(person);
    }

    public List<Person> findAll() {
        return list(namedTypedQuery("${PACKAGE}.core.Person.findAll"));
    }
}
EOF

  write_file "$SRC_MAIN/resources/PeopleResource.java" <<EOF
package ${PACKAGE}.resources;

import ${PACKAGE}.core.Person;
import ${PACKAGE}.db.PersonDAO;
import com.codahale.metrics.annotation.Timed;
import io.dropwizard.hibernate.UnitOfWork;
import jakarta.validation.Valid;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

import java.util.List;

@Path("/people")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class PeopleResource {
    private final PersonDAO dao;

    public PeopleResource(PersonDAO dao) {
        this.dao = dao;
    }

    @POST
    @Timed
    @UnitOfWork
    public Person create(@Valid Person person) {
        return dao.create(person);
    }

    @GET
    @Timed
    @UnitOfWork
    public List<Person> list() {
        return dao.findAll();
    }
}
EOF

  write_file "$SRC_MAIN/resources/PersonResource.java" <<EOF
package ${PACKAGE}.resources;

import ${PACKAGE}.core.Person;
import ${PACKAGE}.db.PersonDAO;
import com.codahale.metrics.annotation.Timed;
import io.dropwizard.hibernate.UnitOfWork;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/people/{id}")
@Produces(MediaType.APPLICATION_JSON)
public class PersonResource {
    private final PersonDAO dao;

    public PersonResource(PersonDAO dao) {
        this.dao = dao;
    }

    @GET
    @Timed
    @UnitOfWork
    public Person get(@PathParam("id") long id) {
        return dao.findById(id).orElseThrow(() -> new NotFoundException("No such person"));
    }
}
EOF
}

generate_person_jdbi() {
  write_file "$SRC_MAIN/core/Person.java" <<EOF
package ${PACKAGE}.core;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotEmpty;
import org.jdbi.v3.core.mapper.reflect.ColumnName;

public class Person {
    private long id;

    @NotEmpty
    private String fullName;

    private String jobTitle;

    public Person() {
        // Jackson / JDBI
    }

    public Person(String fullName, String jobTitle) {
        this.fullName = fullName;
        this.jobTitle = jobTitle;
    }

    @JsonProperty
    public long getId() {
        return id;
    }

    public void setId(long id) {
        this.id = id;
    }

    @JsonProperty
    @ColumnName("full_name")
    public String getFullName() {
        return fullName;
    }

    public void setFullName(String fullName) {
        this.fullName = fullName;
    }

    @JsonProperty
    @ColumnName("job_title")
    public String getJobTitle() {
        return jobTitle;
    }

    public void setJobTitle(String jobTitle) {
        this.jobTitle = jobTitle;
    }
}
EOF

  write_file "$SRC_MAIN/db/PersonDAO.java" <<EOF
package ${PACKAGE}.db;

import ${PACKAGE}.core.Person;
import org.jdbi.v3.sqlobject.config.RegisterBeanMapper;
import org.jdbi.v3.sqlobject.customizer.Bind;
import org.jdbi.v3.sqlobject.customizer.BindBean;
import org.jdbi.v3.sqlobject.statement.GetGeneratedKeys;
import org.jdbi.v3.sqlobject.statement.SqlQuery;
import org.jdbi.v3.sqlobject.statement.SqlUpdate;

import java.util.List;
import java.util.Optional;

@RegisterBeanMapper(Person.class)
public interface PersonDAO {
    @SqlQuery("SELECT id, full_name, job_title FROM people ORDER BY id")
    List<Person> findAll();

    @SqlQuery("SELECT id, full_name, job_title FROM people WHERE id = :id")
    Optional<Person> findById(@Bind("id") long id);

    @SqlUpdate("INSERT INTO people (full_name, job_title) VALUES (:fullName, :jobTitle)")
    @GetGeneratedKeys
    Person create(@BindBean Person person);
}
EOF

  write_file "$SRC_MAIN/resources/PeopleResource.java" <<EOF
package ${PACKAGE}.resources;

import ${PACKAGE}.core.Person;
import ${PACKAGE}.db.PersonDAO;
import com.codahale.metrics.annotation.Timed;
import jakarta.validation.Valid;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

import java.util.List;

@Path("/people")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class PeopleResource {
    private final PersonDAO dao;

    public PeopleResource(PersonDAO dao) {
        this.dao = dao;
    }

    @POST
    @Timed
    public Person create(@Valid Person person) {
        return dao.create(person);
    }

    @GET
    @Timed
    public List<Person> list() {
        return dao.findAll();
    }
}
EOF

  write_file "$SRC_MAIN/resources/PersonResource.java" <<EOF
package ${PACKAGE}.resources;

import ${PACKAGE}.core.Person;
import ${PACKAGE}.db.PersonDAO;
import com.codahale.metrics.annotation.Timed;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/people/{id}")
@Produces(MediaType.APPLICATION_JSON)
public class PersonResource {
    private final PersonDAO dao;

    public PersonResource(PersonDAO dao) {
        this.dao = dao;
    }

    @GET
    @Timed
    public Person get(@PathParam("id") long id) {
        return dao.findById(id).orElseThrow(() -> new NotFoundException("No such person"));
    }
}
EOF
}

generate_auth() {
  write_file "$SRC_MAIN/auth/User.java" <<EOF
package ${PACKAGE}.auth;

import java.security.Principal;
import java.util.Collections;
import java.util.Set;

public class User implements Principal {
    private final String name;
    private final Set<String> roles;

    public User(String name) {
        this(name, Collections.emptySet());
    }

    public User(String name, Set<String> roles) {
        this.name = name;
        this.roles = roles;
    }

    @Override
    public String getName() {
        return name;
    }

    public Set<String> getRoles() {
        return roles;
    }
}
EOF

  write_file "$SRC_MAIN/auth/ExampleAuthenticator.java" <<EOF
package ${PACKAGE}.auth;

import io.dropwizard.auth.Authenticator;
import io.dropwizard.auth.basic.BasicCredentials;

import java.util.Optional;
import java.util.Set;

/**
 * Demo authenticator. Replace with a real user store.
 * Default credentials: user / secret
 */
public class ExampleAuthenticator implements Authenticator<BasicCredentials, User> {
    @Override
    public Optional<User> authenticate(BasicCredentials credentials) {
        if ("secret".equals(credentials.getPassword())) {
            return Optional.of(new User(credentials.getUsername(), Set.of("ADMIN")));
        }
        return Optional.empty();
    }
}
EOF

  write_file "$SRC_MAIN/auth/ExampleAuthorizer.java" <<EOF
package ${PACKAGE}.auth;

import io.dropwizard.auth.Authorizer;
import jakarta.ws.rs.container.ContainerRequestContext;

public class ExampleAuthorizer implements Authorizer<User> {
    @Override
    public boolean authorize(User user, String role, ContainerRequestContext requestContext) {
        return user.getRoles().contains(role);
    }
}
EOF

  write_file "$SRC_MAIN/resources/ProtectedResource.java" <<EOF
package ${PACKAGE}.resources;

import ${PACKAGE}.auth.User;
import io.dropwizard.auth.Auth;
import jakarta.annotation.security.RolesAllowed;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("/protected")
@Produces(MediaType.TEXT_PLAIN)
public class ProtectedResource {
    @GET
    public String showSecret(@Auth User user) {
        return String.format("Hey there, %s. You know the secret!", user.getName());
    }

    @GET
    @Path("/admin")
    @RolesAllowed("ADMIN")
    public String showAdminSecret(@Auth User user) {
        return String.format("Hey there, %s. It looks like you are an admin.", user.getName());
    }
}
EOF
}

generate_views() {
  if has_dep views-freemarker; then
    write_file "$SRC_MAIN/views/HelloView.java" <<EOF
package ${PACKAGE}.views;

import io.dropwizard.views.common.View;

public class HelloView extends View {
    private final String name;

    public HelloView(String name) {
        super("hello.ftl");
        this.name = name;
    }

    public String getName() {
        return name;
    }
}
EOF
    write_file "$PROJECT_DIR/src/main/resources/${PKG_PATH}/views/hello.ftl" <<'EOF'
<#-- @ftlvariable name="" type="__VIEW_TYPE__" -->
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8"/>
    <title>Hello</title>
</head>
<body>
    <h1>Hello, ${name?html}!</h1>
</body>
</html>
EOF
    # rewrite the type hint with the real class
    sed -i.bak "s|__VIEW_TYPE__|${PACKAGE}.views.HelloView|" \
      "$PROJECT_DIR/src/main/resources/${PKG_PATH}/views/hello.ftl"
    rm -f "$PROJECT_DIR/src/main/resources/${PKG_PATH}/views/hello.ftl.bak"
  fi

  if has_dep views-mustache; then
    write_file "$SRC_MAIN/views/HelloMustacheView.java" <<EOF
package ${PACKAGE}.views;

import io.dropwizard.views.common.View;

public class HelloMustacheView extends View {
    private final String name;

    public HelloMustacheView(String name) {
        super("hello.mustache");
        this.name = name;
    }

    public String getName() {
        return name;
    }
}
EOF
    write_file "$PROJECT_DIR/src/main/resources/${PKG_PATH}/views/hello.mustache" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8"/>
    <title>Hello</title>
</head>
<body>
    <h1>Hello, {{name}}!</h1>
</body>
</html>
EOF
  fi

  write_file "$SRC_MAIN/resources/ViewResource.java" <<EOF
package ${PACKAGE}.resources;

$(has_dep views-freemarker && printf 'import %s.views.HelloView;\n' "$PACKAGE")
$(has_dep views-mustache && printf 'import %s.views.HelloMustacheView;\n' "$PACKAGE")
import io.dropwizard.views.common.View;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;

import java.util.Optional;

@Path("/views")
@Produces(MediaType.TEXT_HTML)
public class ViewResource {
    private final String defaultName;

    public ViewResource(String defaultName) {
        this.defaultName = defaultName;
    }
$(has_dep views-freemarker && cat <<'INNER'

    @GET
    @Path("/freemarker")
    public View freemarker(@QueryParam("name") Optional<String> name) {
        return new HelloView(name.orElse(defaultName));
    }
INNER
)
$(has_dep views-mustache && cat <<'INNER'

    @GET
    @Path("/mustache")
    public View mustache(@QueryParam("name") Optional<String> name) {
        return new HelloMustacheView(name.orElse(defaultName));
    }
INNER
)
}
EOF
}

generate_assets() {
  write_file "$PROJECT_DIR/src/main/resources/assets/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8"/>
    <title>${NAME}</title>
</head>
<body>
    <h1>${NAME}</h1>
    <p>${DESCRIPTION}</p>
    <p>Try the JSON API at <a href="/hello-world">/hello-world</a>.</p>
</body>
</html>
EOF
}

generate_migrations() {
  write_file "$PROJECT_DIR/src/main/resources/migrations.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<databaseChangeLog
        xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
         https://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-latest.xsd">

    <changeSet id="1" author="dropwizard-initializr">
        <createTable tableName="people">
            <column name="id" type="bigint" autoIncrement="true">
                <constraints primaryKey="true" nullable="false"/>
            </column>
            <column name="full_name" type="varchar(255)">
                <constraints nullable="false"/>
            </column>
            <column name="job_title" type="varchar(255)"/>
        </createTable>
    </changeSet>
</databaseChangeLog>
EOF
}

generate_tests() {
  if ! has_dep testing; then
    return 0
  fi
  write_file "$SRC_TEST/resources/HelloWorldResourceTest.java" <<EOF
package ${PACKAGE}.resources;

import ${PACKAGE}.api.Saying;
import io.dropwizard.testing.junit5.DropwizardExtensionsSupport;
import io.dropwizard.testing.junit5.ResourceExtension;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;

import static org.assertj.core.api.Assertions.assertThat;

@ExtendWith(DropwizardExtensionsSupport.class)
class HelloWorldResourceTest {
    public final ResourceExtension resources = ResourceExtension.builder()
            .addResource(new HelloWorldResource("Hello, %s!", "Stranger"))
            .build();

    @Test
    void saysHelloWithProvidedName() {
        final Saying saying = resources.target("/hello-world")
                .queryParam("name", "Dropwizard")
                .request()
                .get(Saying.class);

        assertThat(saying.getContent()).isEqualTo("Hello, Dropwizard!");
        assertThat(saying.getId()).isGreaterThan(0);
    }

    @Test
    void saysHelloWithDefaultName() {
        final Saying saying = resources.target("/hello-world")
                .request()
                .get(Saying.class);

        assertThat(saying.getContent()).isEqualTo("Hello, Stranger!");
    }
}
EOF

  write_file "$SRC_TEST/api/SayingTest.java" <<EOF
package ${PACKAGE}.api;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.dropwizard.jackson.Jackson;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class SayingTest {
    private static final ObjectMapper MAPPER = Jackson.newObjectMapper();

    @Test
    void serializesToJson() throws Exception {
        final Saying saying = new Saying(1, "Hello, world!");
        final String json = MAPPER.writeValueAsString(saying);
        assertThat(json).contains("\"id\":1");
        assertThat(json).contains("\"content\":\"Hello, world!\"");
    }

    @Test
    void roundTripsJson() throws Exception {
        final Saying saying = new Saying(2, "Hi");
        final Saying actual = MAPPER.readValue(MAPPER.writeValueAsString(saying), Saying.class);
        assertThat(actual.getId()).isEqualTo(saying.getId());
        assertThat(actual.getContent()).isEqualTo(saying.getContent());
    }
}
EOF
}

generate_docker() {
  local jar_glob entry
  if [ "$TYPE" = maven ]; then
    jar_glob="target/${ARTIFACT}-1.0.0-SNAPSHOT.jar"
    entry="$(cat <<EOF
COPY ${jar_glob} /app/app.jar
COPY config.yml /app/config.yml
EOF
)"
  else
    jar_glob="build/libs/${ARTIFACT}-1.0.0-SNAPSHOT.jar"
    entry="$(cat <<EOF
COPY ${jar_glob} /app/app.jar
COPY config.yml /app/config.yml
EOF
)"
  fi

  write_file "$PROJECT_DIR/Dockerfile" <<EOF
FROM eclipse-temurin:${JAVA_VERSION}-jre-jammy
WORKDIR /app
${entry}
EXPOSE 8080 8081
USER nobody
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
CMD ["server", "/app/config.yml"]
EOF

  write_file "$PROJECT_DIR/.dockerignore" <<'EOF'
.git
.idea
.gradle
build
target
data
*.iml
EOF
}

generate_readme() {
  local build_cmd run_cmd test_cmd jar_path migrate_cmd=""
  if [ "$TYPE" = maven ]; then
    build_cmd="mvn clean package"
    test_cmd="mvn test"
    jar_path="target/${ARTIFACT}-1.0.0-SNAPSHOT.jar"
    run_cmd="java -jar ${jar_path} server config.yml"
  else
    build_cmd="./gradlew build"
    test_cmd="./gradlew test"
    jar_path="build/libs/${ARTIFACT}-1.0.0-SNAPSHOT.jar"
    run_cmd="java -jar ${jar_path} server config.yml"
  fi
  if has_dep migrations; then
    migrate_cmd="java -jar ${jar_path} db migrate config.yml"
  fi

  local dep_list=""
  local d
  local old_ifs="$IFS"
  IFS=','
  for d in $DEPS; do
    [ -z "$d" ] && continue
    dep_list="${dep_list}- \`${d}\` — $(dep_label "$d")
"
  done
  IFS="$old_ifs"
  if [ -n "$(trim "$CUSTOM_DEPS")" ]; then
    local rec group artifact version scope coord
    while IFS= read -r rec; do
      [ -z "$rec" ] && continue
      group="$(printf '%s' "$rec" | cut -f1)"
      artifact="$(printf '%s' "$rec" | cut -f2)"
      version="$(printf '%s' "$rec" | cut -f3)"
      scope="$(printf '%s' "$rec" | cut -f4)"
      if [ -n "$version" ]; then
        coord="${group}:${artifact}:${version}"
      else
        coord="${group}:${artifact}"
      fi
      if [ -n "$scope" ] && [ "$scope" != compile ]; then
        coord="${coord} (${scope})"
      fi
      dep_list="${dep_list}- \`${coord}\` — custom coordinate (build only; no sample code)
"
    done <<EOF
${CUSTOM_DEPS}
EOF
  fi

  write_file "$PROJECT_DIR/README.md" <<EOF
# ${NAME}

${DESCRIPTION}

Generated by **Dropwizard Initializr** for Dropwizard \`${DW_VERSION}\` on Java ${JAVA_VERSION} (${TYPE}).

## Prerequisites

- JDK ${JAVA_VERSION}+
$([ "$TYPE" = maven ] && echo "- Maven 3.6+" || echo "- Gradle 8+ (or use the included wrapper if generated)")

## Build

\`\`\`bash
${build_cmd}
\`\`\`

## Run

\`\`\`bash
${run_cmd}
\`\`\`
$([ -n "$migrate_cmd" ] && printf '\nApply Liquibase migrations first:\n\n```bash\n%s\n```\n' "$migrate_cmd")
The application listens on **8080** (API) and **8081** (admin).

| What | URL |
|------|-----|
| Hello World | http://localhost:8080/hello-world |
| Hello World + name | http://localhost:8080/hello-world?name=Ada |
| Health checks | http://localhost:8081/healthcheck |
| Metrics | http://localhost:8081/metrics |
| Thread dump | http://localhost:8081/threads |
$({ has_dep hibernate || has_dep jdbi3; } && echo "| People API | http://localhost:8080/people |")
$(has_dep auth && echo "| Protected | http://localhost:8080/protected (basic auth \`user\` / \`secret\`) |")
$(has_dep assets && echo "| Static assets | http://localhost:8080/static/ |")
$(has_dep views-freemarker && echo "| FreeMarker view | http://localhost:8080/views/freemarker?name=Ada |")
$(has_dep views-mustache && echo "| Mustache view | http://localhost:8080/views/mustache?name=Ada |")

## Tests

\`\`\`bash
${test_cmd}
\`\`\`

## Dependencies

${dep_list:-"- \`core\` — Jetty, Jersey, Jackson, Metrics, validation"}

Configuration lives in \`config.yml\`. Environment variables are substituted (for example \`DW_DEFAULT_NAME\`).

## Layout

\`\`\`
${ARTIFACT}/
├── config.yml
├── $([ "$TYPE" = maven ] && echo pom.xml || echo "build.gradle")
└── src/
    ├── main/java/${PKG_PATH}/
    │   ├── ${CLASS_PREFIX}Application.java
    │   ├── ${CLASS_PREFIX}Configuration.java
    │   ├── api/
    │   ├── health/
    │   └── resources/
    └── test/java/
\`\`\`
EOF
}

wire_optional_resources() {
  if has_dep views-freemarker || has_dep views-mustache; then
    generate_views
  fi
}

maybe_gradle_wrapper() {
  if [ "$TYPE" != gradle ]; then
    return 0
  fi
  if command -v gradle >/dev/null 2>&1; then
    info "Generating Gradle wrapper..."
    if ! (cd "$PROJECT_DIR" && gradle wrapper --gradle-version 8.14.3 >/dev/null); then
      warn "Gradle wrapper generation failed; you can run 'gradle wrapper' later."
    fi
  else
    warn "gradle not on PATH; skipped wrapper. Run 'gradle wrapper' once Gradle is installed."
  fi
}

maybe_git_init() {
  if [ "$GIT_INIT" != true ]; then
    return 0
  fi
  if ! command -v git >/dev/null 2>&1; then
    warn "git not on PATH; skipped repository init"
    return 0
  fi
  (cd "$PROJECT_DIR" && git init -q && git add . && git commit -q -m "Initial Dropwizard project from Dropwizard Initializr")
  ok "git repository initialized"
}

maybe_zip() {
  if [ "$ZIP" != true ]; then
    return 0
  fi
  local parent base zip_path
  parent="$(cd "$(dirname "$PROJECT_DIR")" && pwd)"
  base="$(basename "$PROJECT_DIR")"
  zip_path="${parent}/${ARTIFACT}.zip"
  (cd "$parent" && rm -f "$zip_path" && zip -qr "$zip_path" "$base")
  ok "Wrote ${zip_path}"
}

print_summary() {
  printf '\n'
  ok "Generated ${NAME}  →  ${PROJECT_DIR}"
  printf '\n'
  printf '  %sGroup%s          %s\n' "${C_BOLD}" "${C_RESET}" "$GROUP"
  printf '  %sArtifact%s       %s\n' "${C_BOLD}" "${C_RESET}" "$ARTIFACT"
  printf '  %sPackage%s        %s\n' "${C_BOLD}" "${C_RESET}" "$PACKAGE"
  printf '  %sDropwizard%s     %s\n' "${C_BOLD}" "${C_RESET}" "$DW_VERSION"
  printf '  %sJava%s           %s\n' "${C_BOLD}" "${C_RESET}" "$JAVA_VERSION"
  printf '  %sBuild%s          %s\n' "${C_BOLD}" "${C_RESET}" "$TYPE"
  printf '  %sDependencies%s   %s\n' "${C_BOLD}" "${C_RESET}" "${DEPS:-core}"
  if [ -n "$(trim "$CUSTOM_DEPS")" ]; then
    local rec group artifact version scope coord
    printf '  %sCustom%s         ' "${C_BOLD}" "${C_RESET}"
    local first="true"
    while IFS= read -r rec; do
      [ -z "$rec" ] && continue
      group="$(printf '%s' "$rec" | cut -f1)"
      artifact="$(printf '%s' "$rec" | cut -f2)"
      version="$(printf '%s' "$rec" | cut -f3)"
      if [ -n "$version" ]; then
        coord="${group}:${artifact}:${version}"
      else
        coord="${group}:${artifact}"
      fi
      if [ "$first" = true ]; then
        printf '%s' "$coord"
        first="false"
      else
        printf ', %s' "$coord"
      fi
    done <<EOF
${CUSTOM_DEPS}
EOF
    printf '\n'
  fi
  if [ -n "$(trim "$UNKNOWN_NOTES")" ]; then
    printf '\n'
    printf '%s' "$UNKNOWN_NOTES" | while IFS= read -r rec; do
      [ -z "$rec" ] && continue
      warn "  $rec"
    done
  fi
  printf '\n%sNext steps%s\n' "${C_BOLD}" "${C_RESET}"
  printf '  cd %s\n' "$PROJECT_DIR"
  if [ "$TYPE" = maven ]; then
    printf '  mvn test\n'
    printf '  mvn package && java -jar target/%s-1.0.0-SNAPSHOT.jar server config.yml\n' "$ARTIFACT"
  else
    if [ -x "$PROJECT_DIR/gradlew" ]; then
      printf '  ./gradlew test\n'
      printf '  ./gradlew run\n'
    else
      printf '  gradle test\n'
      printf '  gradle run\n'
    fi
  fi
  if has_dep migrations; then
    printf '  # after packaging: java -jar <jar> db migrate config.yml\n'
  fi
  printf '\n'
}

generate_project() {
  PROJECT_DIR="$OUTPUT"
  case "$PROJECT_DIR" in
    /*) ;;
    *) PROJECT_DIR="$(pwd)/$PROJECT_DIR" ;;
  esac

  if [ -e "$PROJECT_DIR" ]; then
    if [ "$FORCE" = true ]; then
      rm -rf "$PROJECT_DIR"
    else
      die "directory already exists: $PROJECT_DIR (use --force)"
    fi
  fi

  PKG_PATH="$(printf '%s' "$PACKAGE" | tr '.' '/')"
  SRC_MAIN="$PROJECT_DIR/src/main/java/$PKG_PATH"
  SRC_TEST="$PROJECT_DIR/src/test/java/$PKG_PATH"

  mkdir_p "$SRC_MAIN/api" "$SRC_MAIN/resources" "$SRC_MAIN/health" \
    "$PROJECT_DIR/src/main/resources" \
    "$SRC_TEST/api" "$SRC_TEST/resources"

  generate_gitignore
  generate_banner
  generate_config_yml
  generate_configuration_java
  generate_application_java
  generate_core_java
  generate_tests
  generate_readme

  if [ "$TYPE" = maven ]; then
    generate_pom
  else
    generate_gradle
  fi

  if uses_hibernate_sample; then
    mkdir_p "$SRC_MAIN/core" "$SRC_MAIN/db"
    generate_person_hibernate
  elif uses_jdbi_sample; then
    mkdir_p "$SRC_MAIN/core" "$SRC_MAIN/db"
    generate_person_jdbi
  fi

  if has_dep auth; then
    mkdir_p "$SRC_MAIN/auth"
    generate_auth
  fi

  if has_dep migrations; then
    generate_migrations
  fi

  if has_dep assets; then
    generate_assets
  fi

  if [ "$DOCKER" = true ]; then
    generate_docker
  fi

  wire_optional_resources
  maybe_gradle_wrapper
  maybe_git_init
  maybe_zip
  print_summary
}

launch_ui() {
  local here ui_dir
  here="$(cd "$(dirname "$0")" && pwd)"
  ui_dir="${here}/initializr-ui"
  [ -f "${ui_dir}/server.py" ] || die "UI server not found at ${ui_dir}/server.py"
  command -v python3 >/dev/null 2>&1 || die "python3 is required to serve the UI"
  echo "$UI_PORT" | grep -Eq '^[0-9]+$' || die "invalid --port '$UI_PORT'"
  info "Starting Dropwizard Initializr UI on http://127.0.0.1:${UI_PORT}/"
  exec python3 "${ui_dir}/server.py" --port "$UI_PORT" --generator "${here}/$(basename "$0")"
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --list|--list-dependencies) LIST_ONLY="true"; shift ;;
      --ui) UI_MODE="true"; shift ;;
      --port) UI_PORT="${2-}"; shift 2 ;;
      --defaults) INTERACTIVE="never"; shift ;;
      --interactive) INTERACTIVE="always"; shift ;;
      --force) FORCE="true"; shift ;;
      --zip) ZIP="true"; shift ;;
      --git) GIT_INIT="true"; shift ;;
      --docker) DOCKER="true"; shift ;;
      --group) GROUP="${2-}"; shift 2 ;;
      --artifact) ARTIFACT="${2-}"; shift 2 ;;
      --name) NAME="${2-}"; shift 2 ;;
      --class-name) CLASS_PREFIX="${2-}"; shift 2 ;;
      --description) DESCRIPTION="${2-}"; shift 2 ;;
      --package) PACKAGE="${2-}"; shift 2 ;;
      --java-version|--java) JAVA_VERSION="${2-}"; shift 2 ;;
      --dw-version|--dropwizard-version) DW_VERSION="${2-}"; shift 2 ;;
      --build|--type)
        TYPE="$(lower "${2-}")"
        case "$TYPE" in
          maven-project|mvn) TYPE="maven" ;;
          gradle-project|gradle-groovy|gradle-kotlin) TYPE="gradle" ;;
        esac
        shift 2
        ;;
      --dependencies|--deps) DEPS="${2-}"; shift 2 ;;
      --output|-o) OUTPUT="${2-}"; shift 2 ;;
      --version) printf '%s\n' "$SCRIPT_VERSION"; exit 0 ;;
      --) shift; break ;;
      -*) die "unknown option $1 (try --help)" ;;
      *) die "unexpected argument $1 (try --help)" ;;
    esac
  done
}

apply_defaults() {
  TYPE="$(lower "${TYPE:-$DEFAULT_BUILD}")"
  DW_VERSION="${DW_VERSION:-$DEFAULT_DW_VERSION}"
  JAVA_VERSION="${JAVA_VERSION:-$DEFAULT_JAVA_VERSION}"
  GROUP="${GROUP:-$DEFAULT_GROUP}"
  ARTIFACT="${ARTIFACT:-$DEFAULT_ARTIFACT}"
  NAME="${NAME:-$(to_pascal "$ARTIFACT")}"
  DESCRIPTION="${DESCRIPTION:-$DEFAULT_DESCRIPTION}"
  PACKAGE="${PACKAGE:-${GROUP}.$(to_artifact_suffix "$ARTIFACT")}"
  CLASS_PREFIX="${CLASS_PREFIX:-$(to_pascal "$NAME")}"
  OUTPUT="${OUTPUT:-./$ARTIFACT}"
  if [ -z "$DEPS" ]; then
    normalize_deps "$DEFAULT_DEPS"
  else
    normalize_deps "$DEPS"
  fi
}

main() {
  parse_args "$@"

  if [ "$LIST_ONLY" = true ]; then
    list_dependencies
    exit 0
  fi

  if [ "$UI_MODE" = true ]; then
    launch_ui
  fi

  local should_prompt="false"
  case "$INTERACTIVE" in
    always) should_prompt="true" ;;
    never) should_prompt="false" ;;
    auto)
      if [ -t 0 ] && [ -t 1 ]; then
        # Prompt when the user passed no project-defining flags.
        if [ -z "${GROUP}${ARTIFACT}${NAME}${PACKAGE}${OUTPUT}" ] && [ "${1-}" = "" ]; then
          should_prompt="true"
        fi
      fi
      ;;
  esac

  # Re-evaluate: if launched with zero options on a TTY, run the wizard.
  if [ "$INTERACTIVE" = auto ] && [ -t 0 ] && [ -t 1 ] && [ $# -eq 0 ]; then
    should_prompt="true"
  fi

  if [ "$should_prompt" = true ]; then
    apply_defaults
    run_wizard
    CLASS_PREFIX="${CLASS_PREFIX:-$(to_pascal "$NAME")}"
  else
    apply_defaults
  fi

  validate
  generate_project
}

main "$@"
