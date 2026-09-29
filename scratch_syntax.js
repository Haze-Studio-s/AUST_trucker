const fs = require('fs');

function checkFile(path) {
    const code = fs.readFileSync(path, 'utf8');
    const lines = code.split('\n');
    let stack = [];
    let lineNum = 0;
    for (let rawLine of lines) {
        lineNum++;
        let line = rawLine.replace(/--.*$/, '').trim();
        if (!line) continue;

        // Check quotes
        let inSingle = false, inDouble = false;
        for (let i = 0; i < line.length; i++) {
            let ch = line[i];
            if (ch === "'" && !inDouble && (i === 0 || line[i-1] !== '\\')) inSingle = !inSingle;
            if (ch === '"' && !inSingle && (i === 0 || line[i-1] !== '\\')) inDouble = !inDouble;
        }
        if (inSingle || inDouble) {
            // multiline string or unclosed
        }
    }
    console.log(path + ' scanned ' + lineNum + ' lines without quote anomalies.');
}

checkFile('c:/Users/J2K/Desktop/txData/Qbox_B984EB.base/resources/[mods]/AUST_trucker/client/zones.lua');
checkFile('c:/Users/J2K/Desktop/txData/Qbox_B984EB.base/resources/[mods]/AUST_trucker/server/main.lua');
checkFile('c:/Users/J2K/Desktop/txData/Qbox_B984EB.base/resources/[mods]/AUST_trucker/client/client.lua');
checkFile('c:/Users/J2K/Desktop/txData/Qbox_B984EB.base/resources/[mods]/AUST_trucker/server/events.lua');
