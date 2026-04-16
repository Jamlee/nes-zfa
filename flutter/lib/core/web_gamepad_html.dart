/// Self-contained HTML/JS/CSS for the web virtual gamepad.
/// Served by the in-app HTTP server.
/// URL params: ?player=1&mirror=true
const String webGamepadHtml = r'''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<title>NES Controller</title>
<style>
*{margin:0;padding:0;box-sizing:border-box;-webkit-touch-callout:none;-webkit-user-select:none;user-select:none;touch-action:none}
html,body{width:100%;height:100%;overflow:hidden;color:#fff;font-family:-apple-system,sans-serif}

/* Default (no mirror): solid bg */
body{background:#2d2d2d}
/* Mirror mode: black bg, set by JS */
body.mirror-mode{background:#000}

/* Portrait rotate hint */
#rotate-hint{display:none;position:fixed;inset:0;z-index:999;background:rgba(20,20,20,0.97);flex-direction:column;align-items:center;justify-content:center;gap:16px}
#rotate-hint .icon{font-size:56px;animation:rock 1.5s ease-in-out infinite}
#rotate-hint .msg{font-size:15px;color:rgba(255,255,255,0.6);letter-spacing:1px}
@keyframes rock{0%,100%{transform:rotate(0deg)}50%{transform:rotate(90deg)}}
@media(orientation:portrait){#rotate-hint{display:flex}}

#app{position:relative;width:100%;height:100dvh;height:100%}

/* ===== MIRROR: fullscreen video behind transparent overlay ===== */
#mirror-bg{display:none;position:absolute;inset:0;z-index:0;align-items:center;justify-content:center;background:#000}
#mirror-bg img{width:100%;height:100%;object-fit:contain;image-rendering:pixelated;image-rendering:-webkit-optimize-contrast;image-rendering:crisp-edges}

/* Top bar */
#top-bar{position:absolute;top:0;left:0;right:0;z-index:10;display:flex;align-items:center;justify-content:space-between;padding:4px 16px;height:28px}
body:not(.mirror-mode) #top-bar{background:rgba(0,0,0,0.3)}
body.mirror-mode #top-bar{background:transparent}
#top-bar .badge{font-size:12px;font-weight:700;letter-spacing:2px;color:#e60012}
#top-bar .status{font-size:10px;color:#666}
#top-bar .status.ok{color:#0ab}
#top-bar .status.err{color:#e44}
#top-bar button{background:none;border:1px solid rgba(255,255,255,0.15);border-radius:6px;color:rgba(255,255,255,0.5);font-size:10px;padding:2px 8px}

/* ===== Controller overlay ===== */
#pad{position:absolute;inset:0;z-index:5;display:flex;align-items:center;justify-content:center;padding:28px 0 0 0}

/* No mirror: opaque controls */
body:not(.mirror-mode) #pad{background:none}
/* Mirror: transparent overlay */
body.mirror-mode #pad{background:transparent}

/* Left wing */
#left-wing{flex:1;display:flex;align-items:center;justify-content:center}
#joy-area{position:relative;width:140px;height:140px}
#joy-ring{width:140px;height:140px;border-radius:50%;position:absolute;top:0;left:0}
body:not(.mirror-mode) #joy-ring{background:radial-gradient(circle,#3a3a3a 60%,#333 100%);border:3px solid #444;box-shadow:inset 0 2px 8px rgba(0,0,0,0.5)}
body.mirror-mode #joy-ring{background:radial-gradient(circle,rgba(60,60,60,0.5) 60%,rgba(50,50,50,0.3) 100%);border:3px solid rgba(100,100,100,0.3)}
#joy-knob{width:60px;height:60px;border-radius:50%;position:absolute;top:40px;left:40px}
body:not(.mirror-mode) #joy-knob{background:radial-gradient(circle at 40% 35%,#666,#444);border:2px solid #555;box-shadow:0 2px 8px rgba(0,0,0,0.6),inset 0 1px 2px rgba(255,255,255,0.1)}
body.mirror-mode #joy-knob{background:radial-gradient(circle at 40% 35%,rgba(120,120,120,0.7),rgba(80,80,80,0.5));border:2px solid rgba(150,150,150,0.4);box-shadow:0 2px 8px rgba(0,0,0,0.4)}

/* Center: system buttons at bottom center */
#center-col{position:absolute;bottom:12px;left:50%;transform:translateX(-50%);z-index:6;display:flex;align-items:center;gap:16px}
.sys-btn{width:70px;height:26px;border-radius:13px;display:flex;align-items:center;justify-content:center;font-size:8px;font-weight:700;letter-spacing:2px;cursor:pointer}
body:not(.mirror-mode) .sys-btn{background:linear-gradient(180deg,#555,#444);border:1px solid #666;color:rgba(255,255,255,0.5);box-shadow:0 2px 4px rgba(0,0,0,0.4)}
body.mirror-mode .sys-btn{background:rgba(80,80,80,0.35);border:1px solid rgba(255,255,255,0.15);color:rgba(255,255,255,0.5);backdrop-filter:blur(4px);-webkit-backdrop-filter:blur(4px)}
.sys-btn.active{color:#fff}
body:not(.mirror-mode) .sys-btn.active{background:linear-gradient(180deg,#777,#555)}
body.mirror-mode .sys-btn.active{background:rgba(120,120,120,0.5)}
#reset-btn{width:32px;height:32px;border-radius:50%;background:radial-gradient(circle at 40% 35%,#e60012,#b8000e);border:2px solid #cc0010;display:flex;align-items:center;justify-content:center;font-size:6px;font-weight:800;letter-spacing:1px;color:rgba(255,255,255,0.9);box-shadow:0 2px 6px rgba(230,0,18,0.4);cursor:pointer}
body.mirror-mode #reset-btn{opacity:0.7}
#reset-btn.active{transform:scale(0.93)}

/* Right wing */
#right-wing{flex:1;display:flex;align-items:center;justify-content:center}
#btn-cluster{position:relative;width:180px;height:180px}
.cbtn{position:absolute;width:56px;height:56px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:14px;font-weight:800;cursor:pointer;transition:transform .04s}
body:not(.mirror-mode) .cbtn{box-shadow:0 3px 8px rgba(0,0,0,0.5),inset 0 1px 2px rgba(255,255,255,0.1)}
body.mirror-mode .cbtn{box-shadow:0 2px 6px rgba(0,0,0,0.3)}
.cbtn.active{transform:scale(0.90)}

/* A */
#btn-a{right:0;top:50%;transform:translateY(-50%);color:rgba(255,255,255,0.95)}
body:not(.mirror-mode) #btn-a{background:radial-gradient(circle at 40% 35%,#e65050,#c0392b);border:3px solid #d44}
body.mirror-mode #btn-a{background:radial-gradient(circle at 40% 35%,rgba(230,80,80,0.6),rgba(192,57,43,0.35));border:3px solid rgba(220,68,68,0.5)}
#btn-a.active{transform:translateY(-50%) scale(0.90);box-shadow:0 0 20px rgba(231,76,60,0.5)}

/* B */
#btn-b{bottom:0;left:50%;transform:translateX(-50%);color:rgba(255,255,255,0.9)}
body:not(.mirror-mode) #btn-b{background:radial-gradient(circle at 40% 35%,#f0a030,#d98000);border:3px solid #e6a020}
body.mirror-mode #btn-b{background:radial-gradient(circle at 40% 35%,rgba(240,160,48,0.6),rgba(217,128,0,0.35));border:3px solid rgba(230,160,32,0.5)}
#btn-b.active{transform:translateX(-50%) scale(0.90);box-shadow:0 0 20px rgba(243,156,18,0.5)}

/* TA */
#btn-ta{top:0;left:50%;transform:translateX(-50%);font-size:11px;color:rgba(255,255,255,0.85)}
body:not(.mirror-mode) #btn-ta{background:radial-gradient(circle at 40% 35%,#e65050,#a02020);border:3px solid #c44}
body.mirror-mode #btn-ta{background:radial-gradient(circle at 40% 35%,rgba(230,80,80,0.5),rgba(160,32,32,0.3));border:3px solid rgba(200,68,68,0.4)}
#btn-ta.active{transform:translateX(-50%) scale(0.90);box-shadow:0 0 20px rgba(231,76,60,0.4)}

/* TB */
#btn-tb{left:0;top:50%;transform:translateY(-50%);font-size:11px;color:rgba(255,255,255,0.85)}
body:not(.mirror-mode) #btn-tb{background:radial-gradient(circle at 40% 35%,#e0a030,#b07000);border:3px solid #c89020}
body.mirror-mode #btn-tb{background:radial-gradient(circle at 40% 35%,rgba(224,160,48,0.5),rgba(176,112,0,0.3));border:3px solid rgba(200,144,32,0.4)}
#btn-tb.active{transform:translateY(-50%) scale(0.90);box-shadow:0 0 20px rgba(243,156,18,0.4)}
</style>
</head>
<body tabindex="0" autofocus>
<div id="rotate-hint"><div class="icon">📱</div><div class="msg">Rotate to landscape</div></div>
<div id="app">
  <div id="top-bar">
    <div class="badge">P1</div>
    <div class="status" id="status">Connecting...</div>
    <button onclick="toggleFullscreen()">⛶ Fullscreen</button>
  </div>
  <!-- Mirror: fullscreen video behind everything -->
  <div id="mirror-bg"><img id="stream-img" alt=""></div>
  <!-- Controller overlay -->
  <div id="pad">
    <div id="left-wing">
      <div id="joy-area"><div id="joy-ring"></div><div id="joy-knob"></div></div>
    </div>
    <div id="right-wing">
      <div id="btn-cluster">
        <div class="cbtn" id="btn-ta" data-turbo="a">TA</div>
        <div class="cbtn" id="btn-tb" data-turbo="b">TB</div>
        <div class="cbtn" id="btn-a" data-btn="0">A</div>
        <div class="cbtn" id="btn-b" data-btn="1">B</div>
      </div>
    </div>
  </div>
  <!-- System buttons: bottom center -->
  <div id="center-col">
    <div class="sys-btn" data-btn="2">SELECT</div>
    <div class="sys-btn" data-btn="3">START</div>
    <div id="reset-btn">RESET</div>
  </div>
</div>
<script>
(function(){
  var P=new URLSearchParams(location.search);
  var player=parseInt(P.get('player')||'1');
  var mirror=P.get('mirror')==='true';
  document.querySelector('.badge').textContent='P'+player;

  // Mirror setup
  if(mirror){
    document.body.classList.add('mirror-mode');
    document.getElementById('mirror-bg').style.display='flex';
  }

  // Fullscreen
  window.toggleFullscreen=function(){
    if(!document.fullscreenElement){
      document.documentElement.requestFullscreen().then(function(){document.body.focus();}).catch(function(){});
    }else{document.exitFullscreen();}
  };

  // Auto fullscreen + landscape on first touch
  var req=false;
  document.addEventListener('touchstart',function(){
    if(req)return;req=true;
    if(screen.orientation&&screen.orientation.lock)screen.orientation.lock('landscape').catch(function(){});
    document.documentElement.requestFullscreen().catch(function(){});
  },{once:false,passive:true});

  // ---- WebSocket ----
  var st=document.getElementById('status');
  var streamImg=document.getElementById('stream-img');
  var blobUrl=null;
  var ws=null;

  function connect(){
    var proto=location.protocol==='https:'?'wss:':'ws:';
    ws=new WebSocket(proto+'//'+location.host+'/ws');
    ws.binaryType='arraybuffer';

    ws.onopen=function(){
      st.textContent='Connected';
      st.className='status ok';
      if(mirror){ws.send(JSON.stringify({type:'mirror',active:true}));}
      document.body.focus();
    };

    ws.onclose=function(){
      st.textContent='Reconnecting...';
      st.className='status err';
      frameBuf=null;
      setTimeout(connect,1500);
    };

    ws.onerror=function(){try{ws.close();}catch(e){}};

    // ---- Delta protocol decoder ----
    var W=256,H=240,BPP=4;
    var frameBuf=null;
    var frameNum=0;
    var canvas=null,ctx2d=null;
    var imgData=null;

    if(mirror){
      canvas=document.createElement('canvas');
      canvas.width=W;canvas.height=H;
      ctx2d=canvas.getContext('2d');
      imgData=ctx2d.createImageData(W,H);
      streamImg.style.imageRendering='pixelated';
    }

    function flushFrame(pxFormat){
      if(!frameBuf||!ctx2d)return;
      var d=imgData.data;
      for(var i=0;i<W*H;i++){
        var si=i*4,di=i*4;
        if(pxFormat===0x00){
          d[di]=frameBuf[si+2];
          d[di+1]=frameBuf[si+1];
          d[di+2]=frameBuf[si];
        }else{
          d[di]=frameBuf[si];
          d[di+1]=frameBuf[si+1];
          d[di+2]=frameBuf[si+2];
        }
        d[di+3]=255;
      }
      ctx2d.putImageData(imgData,0,0);
      canvas.toBlob(function(blob){
        if(!blob)return;
        if(blobUrl)URL.revokeObjectURL(blobUrl);
        blobUrl=URL.createObjectURL(blob);
        streamImg.src=blobUrl;
      },'image/png');
    }

    function decodeFullFrame(data,offset,fnum,pxFormat){
      var len=W*H*BPP;
      if(offset+len>data.byteLength)return;
      if(!frameBuf)frameBuf=new Uint8Array(W*H*BPP);
      frameBuf.set(new Uint8Array(data,offset,len));
      frameNum=fnum;
      flushFrame(pxFormat);
    }

    function decodeDeltaFrame(data,offset,fnum,pxFormat){
      if(!frameBuf){
        if(ws&&ws.readyState===1)ws.send(JSON.stringify({type:'keyframe'}));
        return;
      }
      var dv=new DataView(data,offset);
      var blockSize=dv.getUint16(0,true);
      var cols=dv.getUint16(2,true);
      var rows=dv.getUint16(4,true);
      var changedCount=dv.getUint16(6,true);
      var pos=offset+8;
      var blockBytes=blockSize*blockSize*BPP;

      for(var i=0;i<changedCount;i++){
        if(pos+2>data.byteLength)break;
        var blockIdx=new DataView(data,pos).getUint16(0,true);
        pos+=2;
        if(pos+blockBytes>data.byteLength)break;

        var bx=(blockIdx%cols)*blockSize;
        var by=Math.floor(blockIdx/cols)*blockSize;

        var src=new Uint8Array(data,pos,blockBytes);
        for(var py=0;py<blockSize;py++){
          var dstOff=((by+py)*W+bx)*BPP;
          var srcOff=py*blockSize*BPP;
          for(var px=0;px<blockSize*BPP;px++){
            frameBuf[dstOff+px]=src[srcOff+px];
          }
        }
        pos+=blockBytes;
      }

      frameNum=fnum;
      flushFrame(pxFormat);
    }

    ws.onmessage=function(e){
      if(!(e.data instanceof ArrayBuffer))return;
      if(!mirror)return;

      var data=e.data;
      if(data.byteLength<8)return;

      var dv=new DataView(data);
      if(dv.getUint8(0)!==0x4E||dv.getUint8(1)!==0x5A)return;

      var ver=dv.getUint8(2);
      var frameType=dv.getUint8(3);
      var fnum=dv.getUint16(4,true);
      var pxFormat=dv.getUint8(6);

      if(frameType===0x00){
        decodeFullFrame(data,8,fnum,pxFormat);
      }else if(frameType===0x01){
        decodeDeltaFrame(data,8,fnum,pxFormat);
      }
    };
  }
  connect();

  function send(btn,pressed){
    if(ws&&ws.readyState===1)ws.send(JSON.stringify({type:'btn',player:player,btn:btn,pressed:pressed}));
    if(navigator.vibrate&&pressed)navigator.vibrate(10);
  }

  function sendTurbo(which,active){
    if(ws&&ws.readyState===1)ws.send(JSON.stringify({type:'turbo',player:player,btn:which,active:active}));
  }

  // ---- Reset button ----
  var resetEl=document.getElementById('reset-btn');
  resetEl.addEventListener('touchstart',function(e){e.preventDefault();this.classList.add('active');if(ws&&ws.readyState===1)ws.send(JSON.stringify({type:'reset',player:player}));},{passive:false});
  resetEl.addEventListener('touchend',function(e){e.preventDefault();this.classList.remove('active');},{passive:false});
  resetEl.addEventListener('mousedown',function(e){e.preventDefault();this.classList.add('active');if(ws&&ws.readyState===1)ws.send(JSON.stringify({type:'reset',player:player}));});
  resetEl.addEventListener('mouseup',function(){this.classList.remove('active');});

  // ---- Joystick ----
  var zone=document.getElementById('joy-area');
  var knob=document.getElementById('joy-knob');
  var ring=document.getElementById('joy-ring');
  var R=70,Kr=30,DZ=16,MD=R-Kr;
  var joyTouchId=null;
  var joyState={u:false,d:false,l:false,r:false};

  function updateJoy(cx,cy){
    var rect=ring.getBoundingClientRect();
    var dx=cx-(rect.left+R),dy=cy-(rect.top+R);
    var dist=Math.sqrt(dx*dx+dy*dy);
    var nx=dx,ny=dy;
    if(dist>MD){nx=dx/dist*MD;ny=dy/dist*MD;}
    knob.style.left=(R-Kr+nx)+'px';
    knob.style.top=(R-Kr+ny)+'px';
    var u=ny<-DZ,d=ny>DZ,l=nx<-DZ,r=nx>DZ;
    if(u!==joyState.u){joyState.u=u;send(4,u);}
    if(d!==joyState.d){joyState.d=d;send(5,d);}
    if(l!==joyState.l){joyState.l=l;send(6,l);}
    if(r!==joyState.r){joyState.r=r;send(7,r);}
  }

  function resetJoy(){
    knob.style.left=(R-Kr)+'px';knob.style.top=(R-Kr)+'px';
    if(joyState.u){joyState.u=false;send(4,false);}
    if(joyState.d){joyState.d=false;send(5,false);}
    if(joyState.l){joyState.l=false;send(6,false);}
    if(joyState.r){joyState.r=false;send(7,false);}
  }

  zone.addEventListener('touchstart',function(e){e.preventDefault();if(joyTouchId!==null)return;var t=e.changedTouches[0];joyTouchId=t.identifier;updateJoy(t.clientX,t.clientY);},{passive:false});
  zone.addEventListener('touchmove',function(e){e.preventDefault();for(var i=0;i<e.changedTouches.length;i++){var t=e.changedTouches[i];if(t.identifier===joyTouchId){updateJoy(t.clientX,t.clientY);break;}}},{passive:false});
  function endJoy(e){for(var i=0;i<e.changedTouches.length;i++){if(e.changedTouches[i].identifier===joyTouchId){joyTouchId=null;resetJoy();break;}}}
  zone.addEventListener('touchend',endJoy,{passive:false});
  zone.addEventListener('touchcancel',endJoy,{passive:false});

  // ---- Touch buttons (A/B/TA/TB/SELECT/START) ----
  var touchMap=new Map();

  function touchStart(e){
    e.preventDefault();e.stopPropagation();
    for(var i=0;i<e.changedTouches.length;i++){
      var t=e.changedTouches[i];
      var el=document.elementFromPoint(t.clientX,t.clientY);
      if(!el)continue;
      if(el.dataset.btn!==undefined){touchMap.set(t.identifier,el);el.classList.add('active');send(parseInt(el.dataset.btn),true);}
      else if(el.dataset.turbo!==undefined){touchMap.set(t.identifier,el);el.classList.add('active');sendTurbo(el.dataset.turbo,true);}
    }
  }

  function touchEnd(e){
    e.preventDefault();
    for(var i=0;i<e.changedTouches.length;i++){
      var t=e.changedTouches[i];
      var el=touchMap.get(t.identifier);
      if(!el)continue;
      touchMap.delete(t.identifier);
      el.classList.remove('active');
      if(el.dataset.btn!==undefined)send(parseInt(el.dataset.btn),false);
      else if(el.dataset.turbo!==undefined)sendTurbo(el.dataset.turbo,false);
    }
  }

  function touchMove(e){
    e.preventDefault();
    for(var i=0;i<e.changedTouches.length;i++){
      var t=e.changedTouches[i];
      var el=document.elementFromPoint(t.clientX,t.clientY);
      var prev=touchMap.get(t.identifier);
      if(el===prev)continue;
      if(prev){prev.classList.remove('active');if(prev.dataset.btn!==undefined)send(parseInt(prev.dataset.btn),false);else if(prev.dataset.turbo!==undefined)sendTurbo(prev.dataset.turbo,false);}
      if(el&&(el.dataset.btn!==undefined||el.dataset.turbo!==undefined)){touchMap.set(t.identifier,el);el.classList.add('active');if(el.dataset.btn!==undefined)send(parseInt(el.dataset.btn),true);else if(el.dataset.turbo!==undefined)sendTurbo(el.dataset.turbo,true);}
      else{touchMap.delete(t.identifier);}
    }
  }

  var btnCluster=document.getElementById('btn-cluster');
  var centerCol=document.getElementById('center-col');
  [btnCluster,centerCol].forEach(function(area){
    area.addEventListener('touchstart',touchStart,{passive:false});
    area.addEventListener('touchend',touchEnd,{passive:false});
    area.addEventListener('touchcancel',touchEnd,{passive:false});
    area.addEventListener('touchmove',touchMove,{passive:false});
  });

  // ---- Mouse support (desktop testing) ----
  document.querySelectorAll('[data-btn]').forEach(function(el){
    el.addEventListener('mousedown',function(e){e.preventDefault();el.classList.add('active');send(parseInt(el.dataset.btn),true);});
    el.addEventListener('mouseup',function(){el.classList.remove('active');send(parseInt(el.dataset.btn),false);});
    el.addEventListener('mouseleave',function(){if(el.classList.contains('active')){el.classList.remove('active');send(parseInt(el.dataset.btn),false);}});
  });
  document.querySelectorAll('[data-turbo]').forEach(function(el){
    el.addEventListener('mousedown',function(e){e.preventDefault();el.classList.add('active');sendTurbo(el.dataset.turbo,true);});
    el.addEventListener('mouseup',function(){el.classList.remove('active');sendTurbo(el.dataset.turbo,false);});
    el.addEventListener('mouseleave',function(){if(el.classList.contains('active')){el.classList.remove('active');sendTurbo(el.dataset.turbo,false);}});
  });

  // ---- Keyboard bindings ----
  // W/ArrowUp=Up, S/ArrowDown=Down, A/ArrowLeft=Left, D/ArrowRight=Right
  // J=A, K=B, U=TurboA, I=TurboB, Enter=Start, X=Select, Space=Reset
  var KEY_BTN={
    'KeyW':4,'KeyS':5,'KeyA':6,'KeyD':7,
    'KeyJ':0,'KeyK':1,'KeyX':2,'Enter':3,
    'ArrowUp':4,'ArrowDown':5,'ArrowLeft':6,'ArrowRight':7
  };
  var KEY_TURBO={'KeyU':'a','KeyI':'b'};
  var BTN_EL_MAP={0:'[data-btn="0"]',1:'[data-btn="1"]',2:'[data-btn="2"]',3:'[data-btn="3"]',4:null,5:null,6:null,7:null};
  var TURBO_EL_MAP={'a':'#btn-ta','b':'#btn-tb'};
  var pressedKeys={};

  window.addEventListener('keydown',function(e){
    if(e.repeat)return;
    var code=e.code;

    // Button mapping
    if(KEY_BTN[code]!==undefined){
      e.preventDefault();
      var btn=KEY_BTN[code];
      if(!pressedKeys[code]){
        pressedKeys[code]=true;
        send(btn,true);
        var sel=BTN_EL_MAP[btn];
        if(sel){var el=document.querySelector(sel);if(el)el.classList.add('active');}
      }
      return;
    }

    // Turbo mapping
    if(KEY_TURBO[code]!==undefined){
      e.preventDefault();
      var tb=KEY_TURBO[code];
      if(!pressedKeys[code]){
        pressedKeys[code]=true;
        sendTurbo(tb,true);
        var sel2=TURBO_EL_MAP[tb];
        if(sel2){var el2=document.querySelector(sel2);if(el2)el2.classList.add('active');}
      }
      return;
    }

    // Space = reset
    if(code==='Space'){
      e.preventDefault();
      if(ws&&ws.readyState===1)ws.send(JSON.stringify({type:'reset',player:player}));
    }
  },true);

  window.addEventListener('keyup',function(e){
    var code=e.code;
    delete pressedKeys[code];

    if(KEY_BTN[code]!==undefined){
      var btn=KEY_BTN[code];
      send(btn,false);
      var sel=BTN_EL_MAP[btn];
      if(sel){var el=document.querySelector(sel);if(el)el.classList.remove('active');}
      return;
    }

    if(KEY_TURBO[code]!==undefined){
      var tb=KEY_TURBO[code];
      sendTurbo(tb,false);
      var sel2=TURBO_EL_MAP[tb];
      if(sel2){var el2=document.querySelector(sel2);if(el2)el2.classList.remove('active');}
    }
  },true);

})();
</script>
</body>
</html>
''';
