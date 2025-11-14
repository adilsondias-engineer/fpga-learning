using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using System.Collections.ObjectModel;
using _11_mobile_app.Models;
using _11_mobile_app.Services;

namespace _11_mobile_app.ViewModels
{
    /// <summary>
    /// ViewModel for BBO trading terminal
    /// Manages Kafka connection and BBO updates for all symbols
    /// </summary>
    public partial class BboViewModel : ObservableObject
    {
        private MqttConsumerService? _mqttService;

        [ObservableProperty]
        private string _brokerUrl = "192.168.0.2";

        [ObservableProperty]
        private int _port = 1883;

        [ObservableProperty]
        private string _username = "trading";

        [ObservableProperty]
        private string _password = "trading123";

        [ObservableProperty]
        private string _topic = "bbo_messages";

        [ObservableProperty]
        private bool _isConnected;

        [ObservableProperty]
        private string _statusMessage = "Disconnected";

        [ObservableProperty]
        private string _statusColor = "Red";

        [ObservableProperty]
        private int _messageCount;

        [ObservableProperty]
        private BboUpdate? _selectedSymbol;

        public ObservableCollection<BboUpdate> BboUpdates { get; } = new();

        public bool HasBboData => BboUpdates.Count > 0;

        public BboViewModel()
        {
            // Initialize with placeholder data
            StatusMessage = "Ready to connect";
        }

        [RelayCommand]
        private void Connect()
        {
            if (IsConnected)
                return;

            try
            {
                //add username and password - use generated properties
                _mqttService = new MqttConsumerService(BrokerUrl, Port, Topic, Username, Password);

                _mqttService.BboReceived += OnBboReceived;
                _mqttService.ErrorOccurred += OnErrorOccurred;
                _mqttService.ConnectionStateChanged += OnConnectionStateChanged;
                _mqttService.Start();

                StatusMessage = "Connecting...";
                StatusColor = "Orange";
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error: {ex.Message}";
                StatusColor = "Red";
            }
        }

        [RelayCommand]
        private void Disconnect()
        {
            if (!IsConnected)
                return;

            _mqttService?.Stop();
            _mqttService?.Dispose();
            _mqttService = null;

            IsConnected = false;
            StatusMessage = "Disconnected";
            StatusColor = "Red";
        }

        [RelayCommand]
        private void ClearData()
        {
            BboUpdates.Clear();
            MessageCount = 0;
            SelectedSymbol = null;
        }

        private void OnBboReceived(object? sender, BboUpdate bbo)
        {
            // Update or add BBO for this symbol
            var existing = BboUpdates.FirstOrDefault(b => b.Symbol == bbo.Symbol);

            if (existing != null)
            {
                // Update existing
                var index = BboUpdates.IndexOf(existing);
                BboUpdates[index] = bbo;

                // Update selected symbol if it's the same symbol
                if (SelectedSymbol?.Symbol == bbo.Symbol)
                {
                    SelectedSymbol = bbo;
                }
            }
            else
            {
                // Add new symbol
                BboUpdates.Add(bbo);
                OnPropertyChanged(nameof(HasBboData));
            }

            MessageCount++;

            // Auto-select first symbol if none selected
            if (SelectedSymbol == null && BboUpdates.Count > 0)
            {
                SelectedSymbol = BboUpdates[0];
            }
        }

        private void OnErrorOccurred(object? sender, string error)
        {
            StatusMessage = $"Error: {error}";
            StatusColor = "Red";
        }

        private void OnConnectionStateChanged(object? sender, bool connected)
        {
            IsConnected = connected;

            if (connected)
            {
                StatusMessage = $"Connected to {BrokerUrl}";
                StatusColor = "Green";
            }
            else
            {
                StatusMessage = "Disconnected";
                StatusColor = "Red";
            }
        }
    }
}
