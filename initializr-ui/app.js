(function () {
  "use strict";

  var catalog = null;
  var selected = [];
  var nameTouched = false;
  var packageTouched = false;
  var activeResult = -1;

  var $ = function (id) { return document.getElementById(id); };

  function toPascal(value) {
    return String(value || "")
      .split(/[^A-Za-z0-9]+/)
      .filter(Boolean)
      .map(function (part) {
        return part.charAt(0).toUpperCase() + part.slice(1);
      })
      .join("");
  }

  function packageOf(group, artifact) {
    return group + "." + String(artifact || "").toLowerCase().replace(/[^a-z0-9]/g, "");
  }

  function minJava(dw) {
    var found = catalog.dropwizardVersions.find(function (v) { return v.id === dw; });
    return found ? found.minJava : (String(dw).indexOf("5.") === 0 ? 17 : 11);
  }

  function allowedJava(dw) {
    var min = minJava(dw);
    return catalog.javaVersions.filter(function (v) { return parseInt(v, 10) >= min; });
  }

  function fillSelect(el, values, current) {
    el.innerHTML = "";
    values.forEach(function (value) {
      var id = typeof value === "string" ? value : value.id;
      var label = typeof value === "string" ? value : value.name;
      var opt = document.createElement("option");
      opt.value = id;
      opt.textContent = label + (value.recommended ? " (recommended)" : "");
      el.appendChild(opt);
    });
    if (current && values.some(function (v) { return (v.id || v) === current; })) {
      el.value = current;
    }
  }

  function syncPillStyles() {
    document.querySelectorAll("#build-pills label").forEach(function (lab) {
      var on = lab.querySelector("input") && lab.querySelector("input").checked;
      lab.classList.toggle("on", !!on);
    });
  }

  function renderPills() {
    var host = $("build-pills");
    var current = (document.querySelector('input[name="build"]:checked') || {}).value || catalog.defaults.build;
    host.innerHTML = "";
    catalog.builds.forEach(function (b) {
      var lab = document.createElement("label");
      var input = document.createElement("input");
      input.type = "radio";
      input.name = "build";
      input.value = b.id;
      input.checked = b.id === current;
      input.addEventListener("change", syncPillStyles);
      lab.appendChild(input);
      lab.appendChild(document.createTextNode(b.name));
      host.appendChild(lab);
    });
    syncPillStyles();
  }

  function isSelected(id) {
    return selected.some(function (d) { return d.id === id; });
  }

  function addDep(dep) {
    if (isSelected(dep.id)) return;
    selected.push(dep);
    renderChips();
    renderCatalog();
    announce("Added " + dep.id);
    updateCli();
  }

  function removeDep(id) {
    selected = selected.filter(function (d) { return d.id !== id; });
    renderChips();
    renderCatalog();
    announce("Removed " + id);
    updateCli();
  }

  function renderChips() {
    var host = $("chips");
    host.innerHTML = "";
    if (!selected.length) {
      host.innerHTML = '<span class="empty-chips">No extra modules. Core is always included.</span>';
      return;
    }
    selected.forEach(function (dep) {
      var chip = document.createElement("span");
      chip.className = "chip" + (dep.custom ? " custom" : "");
      chip.textContent = dep.name || dep.id;
      var btn = document.createElement("button");
      btn.type = "button";
      btn.setAttribute("aria-label", "Remove " + dep.id);
      btn.textContent = "×";
      btn.addEventListener("click", function () { removeDep(dep.id); });
      chip.appendChild(btn);
      host.appendChild(chip);
    });
  }

  function renderCatalog() {
    var host = $("catalog");
    host.innerHTML = "";
    var groups = [];
    catalog.dependencies.forEach(function (dep) {
      if (groups.indexOf(dep.group) === -1) groups.push(dep.group);
    });
    groups.forEach(function (group) {
      var wrap = document.createElement("div");
      wrap.className = "group";
      var h = document.createElement("h3");
      h.textContent = group;
      wrap.appendChild(h);
      catalog.dependencies.filter(function (d) { return d.group === group; }).forEach(function (dep) {
        var btn = document.createElement("button");
        btn.type = "button";
        btn.className = "dep-btn" + (isSelected(dep.id) ? " added" : "");
        btn.innerHTML = '<span><span class="name">' + dep.name + '</span><div class="meta">' + dep.description + "</div></span><span>" + (isSelected(dep.id) ? "Added" : "Add") + "</span>";
        btn.addEventListener("click", function () {
          if (isSelected(dep.id)) removeDep(dep.id);
          else addDep(dep);
        });
        wrap.appendChild(btn);
      });
      host.appendChild(wrap);
    });
  }

  function searchHits(q) {
    q = q.trim().toLowerCase();
    if (!q) return [];
    return catalog.dependencies.filter(function (dep) {
      var blob = [dep.id, dep.name, dep.description].concat(dep.aliases || []).join(" ").toLowerCase();
      return blob.indexOf(q) !== -1;
    }).slice(0, 8);
  }

  function showResults(items, query) {
    var box = $("results");
    box.innerHTML = "";
    activeResult = -1;
    if (!query) {
      box.classList.remove("open");
      return;
    }
    items.forEach(function (dep, i) {
      var b = document.createElement("button");
      b.type = "button";
      b.setAttribute("role", "option");
      b.dataset.index = String(i);
      b.innerHTML = '<span class="id">' + dep.id + "</span>" + dep.name + '<span class="desc">' + dep.description + "</span>";
      b.addEventListener("click", function () {
        addDep(dep);
        $("dep-search").value = "";
        showResults([], "");
      });
      box.appendChild(b);
    });
    if (!items.length) {
      var custom = document.createElement("button");
      custom.type = "button";
      custom.innerHTML = '<span class="id">custom</span>Add "' + query.replace(/"/g, "") + '"<span class="desc">Unknown ids become build coordinates. Maven GAV is used as-is.</span>';
      custom.addEventListener("click", function () { addCustom(query); });
      box.appendChild(custom);
    }
    box.classList.add("open");
  }

  function addCustom(raw) {
    raw = raw.trim();
    if (!raw) return;
    var known = catalog.dependencies.find(function (d) {
      return d.id === raw.toLowerCase() || (d.aliases || []).indexOf(raw.toLowerCase()) !== -1;
    });
    if (known) {
      addDep(known);
    } else {
      addDep({ id: raw, name: raw, custom: true });
    }
    $("dep-search").value = "";
    showResults([], "");
  }

  function payload() {
    var buildEl = document.querySelector('input[name="build"]:checked');
    var deps = selected.map(function (d) { return d.id; });
    if (deps.indexOf("docker") !== -1) {
      /* catalog docker also toggles the checkbox path via generator */
    }
    return {
      build: buildEl ? buildEl.value : "maven",
      dwVersion: $("dwVersion").value,
      javaVersion: $("javaVersion").value,
      group: $("group").value.trim(),
      artifact: $("artifact").value.trim(),
      name: $("name").value.trim(),
      description: $("description").value.trim(),
      packageName: $("packageName").value.trim(),
      dependencies: deps,
      docker: $("docker").checked || deps.indexOf("docker") !== -1,
      git: $("git").checked
    };
  }

  function cliText(p) {
    var parts = ["./dropwizard-initializr.sh --defaults"];
    parts.push("--build " + p.build);
    parts.push("--dw-version " + p.dwVersion);
    parts.push("--java-version " + p.javaVersion);
    parts.push("--group " + p.group);
    parts.push("--artifact " + p.artifact);
    parts.push('--name "' + p.name.replace(/"/g, '\\"') + '"');
    if (p.dependencies.length) {
      parts.push("--dependencies " + p.dependencies.join(","));
    } else {
      parts.push("--dependencies none");
    }
    if (p.docker) parts.push("--docker");
    if (p.git) parts.push("--git");
    return parts.join(" \\\n  ");
  }

  function updateCli() {
    $("cli").textContent = cliText(payload());
  }

  function toast(msg, isError) {
    var el = $("toast");
    el.textContent = msg;
    el.className = "toast show" + (isError ? " error" : "");
    setTimeout(function () { el.classList.remove("show"); }, 3200);
  }

  function announce(msg) {
    $("announce").textContent = msg;
  }

  function shareUrl(p) {
    var params = new URLSearchParams();
    params.set("type", p.build);
    params.set("groupId", p.group);
    params.set("artifactId", p.artifact);
    params.set("name", p.name);
    params.set("description", p.description);
    params.set("packageName", p.packageName);
    params.set("javaVersion", p.javaVersion);
    params.set("dwVersion", p.dwVersion);
    if (p.dependencies.length) params.set("dependencies", p.dependencies.join(","));
    if (p.docker) params.set("docker", "true");
    if (p.git) params.set("git", "true");
    return location.origin + "/#!" + params.toString();
  }

  function applyHash() {
    if (location.hash.indexOf("#!") !== 0) return;
    var qs = new URLSearchParams(location.hash.slice(2));
    function set(id, key) {
      if (qs.has(key)) $(id).value = qs.get(key);
    }
    if (qs.get("type")) {
      var radio = document.querySelector('input[name="build"][value="' + qs.get("type") + '"]');
      if (radio) radio.checked = true;
    }
    set("group", "groupId");
    set("artifact", "artifactId");
    set("name", "name");
    set("description", "description");
    set("packageName", "packageName");
    if (qs.get("dwVersion")) $("dwVersion").value = qs.get("dwVersion");
    syncJava();
    if (qs.get("javaVersion")) $("javaVersion").value = qs.get("javaVersion");
    $("docker").checked = qs.get("docker") === "true";
    $("git").checked = qs.get("git") === "true";
    nameTouched = qs.has("name");
    packageTouched = qs.has("packageName");
    selected = [];
    (qs.get("dependencies") || "").split(",").filter(Boolean).forEach(function (id) {
      var known = catalog.dependencies.find(function (d) { return d.id === id; });
      addDep(known || { id: id, name: id, custom: true });
    });
  }

  function syncJava() {
    var allowed = allowedJava($("dwVersion").value);
    var current = $("javaVersion").value;
    fillSelect($("javaVersion"), allowed, current);
    if (allowed.indexOf($("javaVersion").value) === -1) {
      $("javaVersion").value = allowed[0];
    }
  }

  function syncDerived() {
    if (!nameTouched) $("name").value = toPascal($("artifact").value) || catalog.defaults.name;
    if (!packageTouched) $("packageName").value = packageOf($("group").value, $("artifact").value);
    updateCli();
  }

  async function generate() {
    var p = payload();
    var btn = $("generate");
    btn.disabled = true;
    try {
      var res = await fetch("/api/generate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(p)
      });
      if (!res.ok) {
        var err = await res.json().catch(function () { return { error: res.statusText }; });
        throw new Error(err.error || "Generate failed");
      }
      var blob = await res.blob();
      var a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = p.artifact + ".zip";
      a.click();
      URL.revokeObjectURL(a.href);
      toast("Downloaded " + p.artifact + ".zip");
    } catch (e) {
      toast(e.message, true);
    } finally {
      btn.disabled = false;
    }
  }

  async function explore() {
    var p = payload();
    $("tree").textContent = "Generating…";
    $("modal").classList.add("open");
    try {
      var res = await fetch("/api/explore", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(p)
      });
      var data = await res.json();
      if (!res.ok) throw new Error(data.error || "Explore failed");
      $("tree").textContent = data.files.map(function (f) {
        return f.path + "  (" + f.size + " bytes)";
      }).join("\n");
    } catch (e) {
      $("tree").textContent = e.message;
    }
  }

  function bind() {
    $("dwVersion").addEventListener("change", function () { syncJava(); updateCli(); });
    $("javaVersion").addEventListener("change", updateCli);
    $("group").addEventListener("input", syncDerived);
    $("artifact").addEventListener("input", syncDerived);
    $("name").addEventListener("input", function () { nameTouched = true; updateCli(); });
    $("description").addEventListener("input", updateCli);
    $("packageName").addEventListener("input", function () { packageTouched = true; updateCli(); });
    $("docker").addEventListener("change", updateCli);
    $("git").addEventListener("change", updateCli);
    $("form").addEventListener("change", function (ev) {
      if (ev.target.name === "build") updateCli();
    });

    var search = $("dep-search");
    search.addEventListener("input", function () {
      showResults(searchHits(search.value), search.value);
    });
    search.addEventListener("keydown", function (ev) {
      var buttons = $("results").querySelectorAll("button");
      if (ev.key === "ArrowDown") {
        ev.preventDefault();
        activeResult = Math.min(activeResult + 1, buttons.length - 1);
      } else if (ev.key === "ArrowUp") {
        ev.preventDefault();
        activeResult = Math.max(activeResult - 1, 0);
      } else if (ev.key === "Enter") {
        ev.preventDefault();
        if (activeResult >= 0 && buttons[activeResult]) buttons[activeResult].click();
        else if (search.value.trim()) addCustom(search.value);
        return;
      } else if (ev.key === "Escape") {
        showResults([], "");
        return;
      } else {
        return;
      }
      buttons.forEach(function (b, i) { b.setAttribute("aria-selected", i === activeResult ? "true" : "false"); });
    });
    document.addEventListener("click", function (ev) {
      if (!$("results").contains(ev.target) && ev.target !== search) showResults([], "");
    });

    $("generate").addEventListener("click", generate);
    $("explore").addEventListener("click", explore);
    $("share").addEventListener("click", function () {
      var url = shareUrl(payload());
      if (navigator.clipboard) navigator.clipboard.writeText(url);
      history.replaceState(null, "", url.slice(url.indexOf("#")));
      toast("Share URL copied");
    });
    $("close-modal").addEventListener("click", function () { $("modal").classList.remove("open"); });
    $("modal").addEventListener("click", function (ev) {
      if (ev.target === $("modal")) $("modal").classList.remove("open");
    });

    document.addEventListener("keydown", function (ev) {
      if ((ev.metaKey || ev.ctrlKey) && ev.key === "Enter") {
        ev.preventDefault();
        generate();
      }
    });
  }

  function applyDefaults() {
    $("group").value = catalog.defaults.group;
    $("artifact").value = catalog.defaults.artifact;
    $("name").value = catalog.defaults.name;
    $("description").value = catalog.defaults.description;
    $("packageName").value = catalog.defaults.packageName;
    fillSelect($("dwVersion"), catalog.dropwizardVersions, catalog.defaults.dwVersion);
    syncJava();
    $("javaVersion").value = catalog.defaults.javaVersion;
    renderPills();
    selected = [];
    catalog.defaults.dependencies.forEach(function (id) {
      var dep = catalog.dependencies.find(function (d) { return d.id === id; });
      if (dep) selected.push(dep);
    });
    renderChips();
    renderCatalog();
    applyHash();
    updateCli();
  }

  fetch("/api/catalog")
    .then(function (r) { return r.json(); })
    .then(function (data) {
      catalog = data;
      bind();
      applyDefaults();
    })
    .catch(function () {
      toast("Could not load catalog. Is the UI server running?", true);
    });
})();
