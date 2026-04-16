// Nez WASM interop — C# [DllImport("__Internal")] → these JS functions
// These are called from NezJsInterop.cs when running on Avalonia Browser.

MergeInto(LibraryManager.library, {
  nez_js_load_rom: function (dataPtr, length) {
    try {
      const nezWasm = window.NezWasm;
      if (!nezWasm || !nezWasm.ready) return 0;
      const romData = new Uint8Array(nezWasm.memory.buffer, dataPtr, length);
      // Copy to a new array since loadRom will use nez_alloc_rom
      const copy = new Uint8Array(romData);
      return nezWasm.loadRom(copy) ? 1 : 0;
    } catch (e) {
      console.error('nez_js_load_rom error:', e);
      return 0;
    }
  },

  nez_js_update: function (dtMs) {
    try {
      const nezWasm = window.NezWasm;
      if (nezWasm && nezWasm.ready) nezWasm.update(dtMs);
    } catch (e) {
      console.error('nez_js_update error:', e);
    }
  },

  nez_js_set_buttons: function (bitmask) {
    try {
      const nezWasm = window.NezWasm;
      if (nezWasm && nezWasm.ready) nezWasm.setButtons(bitmask);
    } catch (_) {}
  },

  nez_js_set_pause: function (paused) {
    try {
      const nezWasm = window.NezWasm;
      if (nezWasm && nezWasm.ready) nezWasm.setPause(!!paused);
    } catch (_) {}
  },

  nez_js_get_framebuffer: function () {
    try {
      const nezWasm = window.NezWasm;
      if (!nezWasm || !nezWasm.ready) return 0;
      const fb = nezWasm.getFrameBuffer();
      if (!fb) return 0;
      // The framebuffer pointer in WASM memory is what we need.
      // nez_framebuffer_get returns the pointer, which is an offset into memory.buffer.
      return nezWasm.exports.nez_framebuffer_get(0);
    } catch (e) {
      console.error('nez_js_get_framebuffer error:', e);
      return 0;
    }
  },
});
