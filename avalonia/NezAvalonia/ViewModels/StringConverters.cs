using System;
using System.Globalization;
using Avalonia.Data.Converters;

namespace NezAvalonia.ViewModels;

/// Shared value converters for XAML bindings.
public static class StringConverters
{
    /// Convert IsRecording (bool) → "Record" or "Stop".
    public static readonly RecordLabelConverter RecordLabel = new();
}

public sealed class RecordLabelConverter : IValueConverter
{
    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        if (value is bool recording)
            return recording ? "Stop" : "Record";
        return "Record";
    }

    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) =>
        throw new NotSupportedException();
}
