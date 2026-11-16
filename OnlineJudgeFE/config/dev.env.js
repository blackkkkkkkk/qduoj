let date = require('moment')().format('YYYYMMDD')

let commit = 'unknown'
try {
  commit = require('child_process').execSync('git rev-parse HEAD').toString().slice(0, 5)
} catch (e) {
  console.warn('[config] not a git repository, use "unknown" as commit hash')
}

let version = `"${date}-${commit}"`

console.log(`current version is ${version}`)

module.exports = {
  NODE_ENV: '"development"',
  VERSION: version,
  USE_SENTRY: '0'
}