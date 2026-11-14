// Type-checks contents/code/main.js with TypeScript (strict, JSDoc types),
// without changing what KWin runs: main.js stays plain JavaScript.
//
// main.js starts with QML's `.pragma library`, which is not JavaScript, so
// tsc checks a copy with that line commented out (line numbers unchanged,
// as in the unit tests) and reports against the real file.
//
// Usage: node tests/typecheck.mjs   (tsc from $TSC, the PATH or
// /opt/kso-tools/bin; dev/setup-container.sh installs the pinned version.)
// KSO_ROOT=/path/to/copy checks another checkout.
import { mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const ROOT = process.env.KSO_ROOT || fileURLToPath(new URL('..', import.meta.url))
const SOURCE = 'contents/code/main.js'

function findTsc() {
    if (process.env.TSC) return process.env.TSC
    for (const dir of (process.env.PATH || '').split(':').concat('/opt/kso-tools/bin')) {
        if (dir && existsSync(join(dir, 'tsc'))) return join(dir, 'tsc')
    }
    console.error('tsc not found: run dev/setup-container.sh (or set TSC=/path/to/tsc)')
    process.exit(2)
}

const src = readFileSync(join(ROOT, SOURCE), 'utf8')
if (!/^\s*\.pragma library\s*$/m.test(src)) {
    console.error(SOURCE + ': expected a `.pragma library` line')
    process.exit(2)
}
const dir = mkdtempSync(join(tmpdir(), 'kso-typecheck-'))
try {
    writeFileSync(join(dir, 'main.js'), src.replace(/^(\s*)\.pragma library/m, '$1// .pragma library'))
    writeFileSync(join(dir, 'tsconfig.json'), JSON.stringify({
        compilerOptions: {
            allowJs: true,
            checkJs: true,
            noEmit: true,
            strict: true,
            noImplicitReturns: true,
            noFallthroughCasesInSwitch: true,
            noUnusedLocals: true,
            noUnusedParameters: true,
            // KWin's QML engine: modern ECMAScript, no DOM, no Node.
            target: 'ES2020',
            lib: ['ES2020'],
            types: [],
        },
        files: ['main.js'],
    }))
    // Run from the copy's folder, so tsc names the file plain `main.js`.
    const r = spawnSync(findTsc(), ['-p', '.', '--pretty', 'false'], { cwd: dir, encoding: 'utf8' })
    if (r.error) {
        console.error('could not run tsc: ' + r.error.message)
        process.exitCode = 2
    } else if (r.status === 0) {
        console.log(SOURCE + ': no type errors')
    } else {
        process.stdout.write((r.stdout + r.stderr).replace(/^main\.js\(/gm, SOURCE + '('))
        process.exitCode = r.status === null ? 2 : r.status
    }
} finally {
    rmSync(dir, { recursive: true, force: true })
}
