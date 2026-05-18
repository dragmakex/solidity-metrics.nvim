const fs = require('fs');
const path = require('path');
const { createRequire } = require('module');

function fail(message) {
  process.stderr.write(String(message) + '\n');
  process.exit(1);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function normalize(p) {
  return p.replace(/\\/g, '/');
}

function isSolidityFile(filePath) {
  return path.extname(filePath) === '.sol';
}

function toGlobSet(globs) {
  if (!globs || globs.length === 0) {
    return undefined;
  }
  return '{' + globs.join(',') + '}';
}

function getWsGitInfo(rootPath) {
  let branch = 'unknown_branch';
  let commit = 'unknown_commit';
  let remote = '';

  if (!rootPath) {
    return { branch, commit, remote };
  }

  const headPath = path.join(rootPath, '.git', 'HEAD');
  if (!fs.existsSync(headPath)) {
    return { branch, commit, remote };
  }

  let branchFile = fs.readFileSync(headPath, 'utf8').trim();
  if (!branchFile.startsWith('ref: ')) {
    return { branch, commit, remote };
  }

  branchFile = branchFile.replace('ref: ', '');
  const branchPath = path.normalize(path.join(rootPath, '.git', branchFile));
  if (!branchPath.startsWith(path.normalize(rootPath)) || !fs.existsSync(branchPath)) {
    return { branch, commit, remote };
  }

  branch = branchFile.replace('refs/heads/', '');
  commit = fs.readFileSync(branchPath, 'utf8').trim();

  const fetchHeadPath = path.join(rootPath, '.git', 'FETCH_HEAD');
  if (!fs.existsSync(fetchHeadPath)) {
    return { branch, commit, remote };
  }

  const fetchHeadData = fs.readFileSync(fetchHeadPath, 'utf8').trim().split(/\r?\n/);
  const fetchHead =
    fetchHeadData.find((line) => line.startsWith(commit)) ||
    fetchHeadData.find((line) => line.includes(`branch '${branch}' of `)) ||
    fetchHeadData[0];

  if (fetchHead) {
    remote = fetchHead.trim().split(/\s+/).pop() || '';
  }

  return { branch, commit, remote };
}

function collectMatches(glob, cwd, matcher) {
  return matcher.sync(glob, { cwd, nodir: true, absolute: true }).map((file) => path.normalize(file));
}

function addFile(metrics, filePath) {
  if (isSolidityFile(filePath) && fs.existsSync(filePath)) {
    metrics.analyze(filePath);
  }
}

function addTruffleLocations(metrics, root, matcher, excludeGlobs) {
  const matches = matcher.sync('**/truffle*.js', {
    cwd: root,
    nodir: true,
    absolute: true,
    ignore: excludeGlobs,
  });

  for (const filePath of matches) {
    metrics.addTruffleProjectLocation(path.normalize(filePath));
  }
}

function addExcludedFiles(metrics, root, matcher, excludeGlobs) {
  const expanded = [];
  for (const glob of excludeGlobs || []) {
    expanded.push(glob.endsWith('.sol') ? glob : path.posix.join(glob, '**/*.sol'));
  }

  for (const glob of expanded) {
    const matches = matcher.sync(glob, { cwd: root, nodir: true, absolute: true });
    for (const filePath of matches) {
      metrics.addExcludedFile(path.normalize(filePath));
    }
  }
}

function getRisks(inputJson) {
  const avgSummary = inputJson.avg.summary;
  const totalSummary = inputJson.totals.summary;
  const keys = Array.from(new Set([...Object.keys(avgSummary), ...Object.keys(totalSummary)]));
  return {
    keys,
    avg: keys.map((key) => avgSummary[key] || 0),
    totals: keys.map((key) => totalSummary[key] || 0),
  };
}

function getSloc(inputJson) {
  const keys = Object.keys(inputJson.totals.nsloc).filter((key) => key !== 'total' && key !== 'commentToSourceRatio');
  return {
    keys,
    sloc: keys.map((key) => inputJson.totals.sloc[key] || 0),
    nsloc: keys.map((key) => inputJson.totals.nsloc[key] || 0),
  };
}

function getNum(inputJson) {
  const keys = Object.keys(inputJson.totals.num);
  return {
    keys,
    avg: keys.map((key) => inputJson.avg.num[key] || 0),
    totals: keys.map((key) => inputJson.totals.num[key] || 0),
  };
}

function getNumAst(inputJson, filterKey) {
  const keys = Object.keys(inputJson.totals.ast).filter((key) => {
    const value = inputJson.totals.ast[key];
    return typeof value === 'number' && (filterKey === undefined || filterKey(key));
  });
  return {
    keys,
    avg: keys.map((key) => inputJson.avg.ast[key] || 0),
    totals: keys.map((key) => inputJson.totals.ast[key] || 0),
  };
}

async function generateReport(request, metricsPackageRoot) {
  metricsPackageRoot = path.resolve(metricsPackageRoot);
  const packageJsonPath = path.join(metricsPackageRoot, 'package.json');
  const requireFromPackage = createRequire(packageJsonPath);
  const { SolidityMetricsContainer } = requireFromPackage('./src/index.js');
  const glob = requireFromPackage('glob');
  let exportAsHtml;
  if (request.output_html) {
    ({ exportAsHtml } = requireFromPackage('./src/metrics/helper.js'));
  }

  const excludeGlobs = request.exclude || [];
  const baseOptions = {
    basePath: normalize(request.root) + '/',
    inputFileGlobExclusions: toGlobSet(excludeGlobs),
    inputFileGlob: undefined,
    inputFileGlobLimit: request.limit,
    debug: false,
    repoInfo: getWsGitInfo(request.root),
  };

  const metrics = new SolidityMetricsContainer(request.display_name || path.basename(request.root), baseOptions);

  if (request.kind === 'file') {
    metrics.inputFileGlob = normalize(request.file).replace(metrics.basePath, '');
    addFile(metrics, request.file);
  } else if (request.kind === 'workspace') {
    metrics.inputFileGlob = '**/*.sol';
    for (const filePath of request.selected_files || []) {
      addFile(metrics, filePath);
    }
    addTruffleLocations(metrics, request.root, glob, excludeGlobs);
    addExcludedFiles(metrics, request.root, glob, excludeGlobs);
  } else if (request.kind === 'scope') {
    const scopeFileContent = fs.readFileSync(request.scope_file, 'utf8');
    const scopeFileDir = path.dirname(request.scope_file);
    const patterns = scopeFileContent.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
    metrics.inputFileGlob = '{' + patterns.join(',') + '}';

    for (const globPattern of patterns) {
      const resolvedGlob = path.join(scopeFileDir, globPattern);
      const matches = collectMatches(resolvedGlob, request.root, glob);
      for (const filePath of matches) {
        addFile(metrics, filePath);
      }
    }
  } else {
    throw new Error(`Unsupported request kind: ${request.kind}`);
  }

  if (!metrics.seenFiles.length) {
    throw new Error('No valid solidity source files found.');
  }

  let dotGraphs = {};
  try {
    dotGraphs = metrics.getDotGraphs();
  } catch (_error) {
    dotGraphs = {};
  }

  const totals = metrics.totals();
  const markdown = await metrics.generateReportMarkdown();

  if (request.output_html) {
    return { __html: exportAsHtml(markdown, totals, dotGraphs) };
  }

  return {
    markdown,
    totals,
    dot_graphs: dotGraphs,
    charts: {
      risk: getRisks(totals),
      sloc: getSloc(totals),
      summary: getNum(totals),
      ast: getNumAst(totals, (key) => !key.startsWith('FunctionCall:Name:') && !key.startsWith('AssemblyCall:Name:')),
      function_calls: getNumAst(totals, (key) => key.startsWith('FunctionCall:Name:')),
      assembly_calls: getNumAst(totals, (key) => key.startsWith('AssemblyCall:Name:')),
    },
  };
}

async function main() {
  const requestPath = process.argv[2];
  const metricsPackageRoot = process.argv[3];

  if (!requestPath || !metricsPackageRoot) {
    fail('usage: node scripts/report_data.js <request.json> <metrics-package-root>');
  }

  try {
    const request = readJson(requestPath);
    const report = await generateReport(request, metricsPackageRoot);
    if (request.output_html) {
      process.stdout.write(report.__html);
    } else {
      process.stdout.write(JSON.stringify(report));
    }
  } catch (error) {
    fail(error && error.stack ? error.stack : error);
  }
}

main();
