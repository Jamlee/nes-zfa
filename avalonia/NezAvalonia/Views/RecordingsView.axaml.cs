using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Interactivity;
using NezAvalonia.ViewModels;

namespace NezAvalonia.Views;

public partial class RecordingsView : UserControl
{
    public RecordingsView()
    {
        InitializeComponent();
    }

    private void OnRecordingClick(object? sender, PointerPressedEventArgs e)
    {
        if (sender is Border border && border.DataContext is RecordingEntry entry)
        {
            if (DataContext is RecordingsViewModel vm)
            {
                vm.PreviewCommand.Execute(entry);
            }
        }
    }

    private void OnPreviewOverlayClick(object? sender, PointerPressedEventArgs e)
    {
        if (DataContext is RecordingsViewModel vm)
        {
            vm.ClosePreviewCommand.Execute(null);
        }
    }
}
