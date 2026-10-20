const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('C:/Users/User/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
(async () => {
  const out = __dirname;
  const browser = await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true,args:['--allow-file-access-from-files']});
  try {
    const page = await browser.newPage({viewport:{width:1280,height:720}});
    await page.goto('file:///D:/Downloads/368132.mp4');
    await page.waitForFunction(() => document.querySelector('video')?.readyState >= 2, {timeout:30000});
    const metadata = await page.evaluate(() => {const v=document.querySelector('video');v.pause();v.controls=false;v.style='position:fixed;inset:0;width:100vw;height:100vh;background:black;object-fit:contain'; return {duration:v.duration,width:v.videoWidth,height:v.videoHeight};});
    fs.writeFileSync(path.join(out,'video-metadata.json'),JSON.stringify(metadata,null,2)+'\n');
    const times = [0.5,2,4,6,8,10,12,14,16,18].filter(t => t < metadata.duration);
    for (const t of times) {
      await page.evaluate(t => new Promise(resolve => {const v=document.querySelector('video');v.onseeked=()=>resolve();v.currentTime=t;}),t);
      await page.screenshot({path:path.join(out,`reference-${String(t).replace('.','_')}.png`)});
    }
    console.log(JSON.stringify({metadata,times}));
  } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exitCode=1});
