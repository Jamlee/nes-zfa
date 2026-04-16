using System;

namespace NezAvalonia.Core;

/// <summary>
/// Factory for creating the appropriate NES engine based on the current platform.
/// On Browser (WASM), creates NezWasmEngine; on Desktop/Android, creates NezEngine.
/// </summary>
public static class NezEngineFactory
{
#if BROWSER
    public static INezEngine Create() => new NezWasmEngine();
#else
    public static INezEngine Create() => new NezEngine();
#endif
}
