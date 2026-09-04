# Dropwizard Initializr

A [start.spring.io](https://start.spring.io)-style project generator for [Dropwizard](https://www.dropwizard.io/).

Generate a runnable Maven or Gradle service from a CLI wizard, flags, or a local web UI. Catalog modules (Hibernate, JDBI, auth, migrations, views, …) get sample code; unknown names and Maven coordinates are still added to the build.

## Requirements

- Bash 3.2+ (macOS `/bin/bash` is fine)
- JDK 17+ for Dropwizard 5.x (Java 11+ for 3.x / 4.x)
- Maven 3.6+ and/or Gradle 8+ for the generated project
- Python 3.9+ only if you use the web UI

## Install

```bash
git clone https://github.com/paul-tinius/dropwizard-initializr.git
cd dropwizard-initializr
chmod +x dropwizard-initializr.sh
```

Keep `dropwizard-initializr.sh` next to the `initializr-ui/` directory so `--ui` can find the server.

## Web UI

```bash
./dropwizard-initializr.sh --ui
# optional: --port 9000
```

Opens `http://127.0.0.1:8088/`. Choose Maven/Gradle, Dropwizard and Java versions, metadata, and dependencies, then **Generate** (downloads a zip), **Explore** (file tree), or **Share** (URL that restores the form).

The same server speaks a Spring Initializr-style download API:

```bash
curl -OJ 'http://127.0.0.1:8088/starter.zip?type=maven&groupId=com.acme&artifactId=hello-world&dependencies=auth,hibernate'
```

## CLI

Interactive wizard:

```bash
./dropwizard-initializr.sh
```

Non-interactive:

```bash
./dropwizard-initializr.sh \
  --group com.acme \
  --artifact hello-world \
  --name HelloWorld \
  --java-version 17 \
  --dw-version 5.0.2 \
  --build gradle \
  --dependencies auth,hibernate,migrations,postgresql \
  --docker --git \
  --output ./hello-world
```

```bash
./dropwizard-initializr.sh --list
./dropwizard-initializr.sh --defaults
```

### Flags

| Flag | Meaning |
|------|---------|
| `--group`, `--artifact`, `--name`, `--package` | Maven/Gradle coordinates and Java package |
| `--description` | Project description |
| `--java-version` | 11, 17, 21, or 25 |
| `--dw-version` | Dropwizard version (default `5.0.2`) |
| `--build maven\|gradle` | Build tool |
| `--dependencies` | Catalog ids, aliases, or `group:artifact[:version[:scope]]` |
| `--docker` | Include a Dockerfile |
| `--git` | `git init` in the generated project |
| `--zip` | Also write `<artifact>.zip` |
| `--force` | Overwrite an existing output directory |
| `--ui` / `--port` | Local web UI |

## Dependencies

`dropwizard-core` is always included. `testing` is added unless you pass `none` or `no-testing`.

**Web:** `testing`, `auth`, `client`, `forms`, `assets`, `views-freemarker`, `views-mustache`, `http2`  
**Data:** `hibernate`, `jdbi3`, `migrations`, `h2`, `postgresql`, `mysql`  
**Ops:** `json-logging`, `metrics-graphite`, `docker`

Aliases: `jpa` → hibernate, `jdbc` → jdbi3, `liquibase` → migrations, `security` → auth, `postgres` → postgresql, `views` → views-freemarker.

Unknown ids are not rejected:

- Catalog typos (`hibernat`) are auto-corrected
- `group:artifact[:version[:scope]]` is written into the POM / `build.gradle`
- A bare name such as `redis` becomes `io.dropwizard:dropwizard-redis`

Custom coordinates get no sample Java — only build entries.

## Generated project

A typical Maven tree:

```text
hello-world/
├── config.yml
├── pom.xml
├── Dockerfile          # if --docker
└── src/main/java/.../
    ├── HelloWorldApplication.java
    ├── HelloWorldConfiguration.java
    ├── api/
    ├── health/
    └── resources/
```

```bash
cd hello-world
mvn test
mvn package
java -jar target/hello-world-1.0.0-SNAPSHOT.jar server config.yml
```

Gradle projects include a wrapper when `gradle` is on `PATH`. Run with `./gradlew run`.

## Layout of this repository

```text
dropwizard-initializr.sh   # CLI wizard + generator
initializr-ui/             # local web UI
  catalog.json             # versions and module catalog
  server.py                # stdlib HTTP server; shells out to the script
  index.html / app.js / styles.css
```

## License

Apache License 2.0. See [LICENSE](LICENSE).
