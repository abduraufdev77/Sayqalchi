using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using Sayqalchi.Core;

namespace Sayqalchi.Windows;
public partial class MainWindow : Window
{
    private readonly Controller controller;
    internal MainWindow(Controller controller)
    {
        this.controller = controller; InitializeComponent(); DataContext = controller;
        DefaultToolBox.ItemsSource = Enum.GetValues<Tool>(); DefaultToolBox.SelectedItem = controller.Settings.DefaultTool;
        CustomProvider.IsChecked = controller.Settings.CustomProvider; ServiceUrl.Text = controller.Settings.ServiceUrl;
        ApiKey.Password = controller.Settings.ReadToken(); AllowHttp.IsChecked = controller.Settings.AllowHttp;
        Exclusions.Text = string.Join(", ", controller.Settings.ExcludedProcesses);
        Closing += (_, e) => { e.Cancel = true; Hide(); };
    }
    private void PlaygroundClick(object sender, RoutedEventArgs e) { PlaygroundPane.Visibility = Visibility.Visible; SettingsPane.Visibility = Visibility.Collapsed; PageTitle.Text = "Playground"; }
    private void SettingsClick(object sender, RoutedEventArgs e) { PlaygroundPane.Visibility = Visibility.Collapsed; SettingsPane.Visibility = Visibility.Visible; PageTitle.Text = "Settings"; }
    private void ToggleClick(object sender, RoutedEventArgs e) => controller.Toggle();
    private void ToolClick(object sender, RoutedEventArgs e) { if (sender is Button { Tag: string name } && Enum.TryParse<Tool>(name, out var tool)) controller.SelectTool(tool); }
    private void CopyClick(object sender, RoutedEventArgs e) => controller.Copy();
    private void MoreClick(object sender, RoutedEventArgs e) => controller.More();
    private void DefaultChanged(object sender, SelectionChangedEventArgs e) { if (IsLoaded && DefaultToolBox.SelectedItem is Tool tool) controller.SetDefault(tool); }
    private void SaveClick(object sender, RoutedEventArgs e)
    {
        try
        {
            if (CustomProvider.IsChecked == true) WritingServices.CustomEndpoint(new(true, ServiceUrl.Text, ApiKey.Password, AllowHttp.IsChecked == true));
            controller.Settings.SaveToken(ApiKey.Password); controller.Settings.CustomProvider = CustomProvider.IsChecked == true;
            controller.Settings.ServiceUrl = ServiceUrl.Text.Trim(); controller.Settings.AllowHttp = AllowHttp.IsChecked == true;
            controller.Settings.ExcludedProcesses = Exclusions.Text.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
            controller.Settings.Save(); SettingsNotice.Text = "Settings saved.";
        }
        catch (Exception error) when (error is not OutOfMemoryException) { SettingsNotice.Text = "Could not save. Check the service URL, key and your Windows profile’s write access."; }
    }
    private void PrivacyClick(object sender, RoutedEventArgs e) => Process.Start(new ProcessStartInfo("https://mymemory.translated.net/doc/usagelimits.php") { UseShellExecute = true });
}
