using _11_mobile_app.Models;
using MQTTnet;
using MQTTnet.Packets;
using MQTTnet.Protocol;
using System.Text;
using System.Text.Json;

namespace _11_mobile_app.Services
{
    /// <summary>
    /// MQTT consumer service for real-time BBO updates from FPGA trading system
    /// Connects to MQTT broker and streams BBO messages
    /// </summary>
    public class MqttConsumerService : IDisposable
    {
        private IMqttClient? _mqttClient;
        private CancellationTokenSource? _cancellationTokenSource;

        public event EventHandler<BboUpdate>? BboReceived;
        public event EventHandler<string>? ErrorOccurred;
        public event EventHandler<bool>? ConnectionStateChanged;

        public bool IsConnected { get; private set; }

        private readonly string _brokerUrl;
        private readonly int _port;
        private readonly string _topic;
        private readonly string _username;
        private readonly string _password;

        public MqttConsumerService(string brokerUrl, int port, string topic, string username, string password)
        {
            _brokerUrl = brokerUrl;
            _port = port;
            _topic = topic;
            _username = username;
            _password = password;
        }

        /// <summary>
        /// Start consuming MQTT messages in background
        /// </summary>
        public async void Start()
        {
            if (_mqttClient != null && _mqttClient.IsConnected)
                return; // Already running

            try
            {
                var factory = new MqttClientFactory();
                _mqttClient = factory.CreateMqttClient();

                // Setup message handler
                _mqttClient.ApplicationMessageReceivedAsync += OnMessageReceived;

                // Setup disconnect handler for debugging
                _mqttClient.DisconnectedAsync += async e =>
                {
                    await MainThread.InvokeOnMainThreadAsync(() =>
                    {
                        var reason = e.Reason.ToString();
                        var reasonString = e.ReasonString ?? "No details";
                        ErrorOccurred?.Invoke(this, $"Disconnected: {reason} - {reasonString}");
                    });
                };

                // Create options with timeout
                // Force MQTT v3.1.1 for compatibility (ESP32 likely uses this)
                var optionsBuilder = new MqttClientOptionsBuilder()
                    .WithProtocolVersion(MQTTnet.Formatter.MqttProtocolVersion.V311)
                    .WithTcpServer(_brokerUrl, _port)
                    .WithClientId($"maui-mobile-app-{Guid.NewGuid()}")
                    .WithCleanSession()
                    .WithKeepAlivePeriod(TimeSpan.FromSeconds(60))
                    .WithTimeout(TimeSpan.FromSeconds(10));

                // Add credentials if provided (check for null/empty)
                if (!string.IsNullOrWhiteSpace(_username) && !string.IsNullOrWhiteSpace(_password))
                {
                    optionsBuilder.WithCredentials(_username, _password);
                    Console.WriteLine($"Connecting with credentials: {_username} / {new string('*', _password.Length)}");
                }
                else
                {
                    Console.WriteLine("Connecting without credentials");
                }

                var options = optionsBuilder.Build();

                Console.WriteLine($"Attempting connection to {_brokerUrl}:{_port}");

                // Connect with cancellation token
                var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15));
                var response = await _mqttClient.ConnectAsync(options, cts.Token);

                Console.WriteLine($"Connection result: {response.ResultCode}");
                Console.WriteLine($"Reason: {response.ReasonString}");
                Console.WriteLine($"IsSessionPresent: {response.IsSessionPresent}");

                if (response.ResultCode == MqttClientConnectResultCode.Success)
                {
                    IsConnected = true;
                    await MainThread.InvokeOnMainThreadAsync(() =>
                    {
                        ConnectionStateChanged?.Invoke(this, true);
                    });

                    // Subscribe to topic
                    Console.WriteLine($"Subscribing to topic: {_topic}");
                    var subscribeResult = await _mqttClient.SubscribeAsync(_topic);
                    Console.WriteLine($"Subscribe result: {subscribeResult.Items.Count} items");

                    foreach (var item in subscribeResult.Items)
                    {
                        Console.WriteLine($"  Topic: {item.TopicFilter.Topic}, ResultCode: {item.ResultCode}");
                    }
                }
                else
                {
                    var errorMsg = $"Connection failed: {response.ResultCode}";
                    if (!string.IsNullOrEmpty(response.ReasonString))
                    {
                        errorMsg += $" - {response.ReasonString}";
                    }

                    await MainThread.InvokeOnMainThreadAsync(() =>
                    {
                        ErrorOccurred?.Invoke(this, errorMsg);
                    });
                }
            }
            catch (OperationCanceledException)
            {
                await MainThread.InvokeOnMainThreadAsync(() =>
                {
                    ErrorOccurred?.Invoke(this, "Connection timeout - check broker is running and reachable");
                });
            }
            catch (Exception ex)
            {
                var errorMsg = $"Connection error: {ex.Message}";
                if (ex.InnerException != null)
                {
                    errorMsg += $" | Inner: {ex.InnerException.Message}";
                }

                Console.WriteLine($"Exception: {ex}");

                await MainThread.InvokeOnMainThreadAsync(() =>
                {
                    ErrorOccurred?.Invoke(this, errorMsg);
                });
            }
        }

        /// <summary>
        /// Stop consuming messages
        /// </summary>
        public async void Stop()
        {
            if (_mqttClient != null && _mqttClient.IsConnected)
            {
                await _mqttClient.DisconnectAsync();
            }

            IsConnected = false;
            await MainThread.InvokeOnMainThreadAsync(() =>
            {
                ConnectionStateChanged?.Invoke(this, false);
            });
        }

        private async Task OnMessageReceived(MqttApplicationMessageReceivedEventArgs e)
        {
            try
            {
                var payload = System.Text.Encoding.UTF8.GetString(e.ApplicationMessage.Payload);

                // Parse JSON to BboUpdate
                var bbo = JsonSerializer.Deserialize<BboUpdate>(payload);

                if (bbo != null)
                {
                    bbo.LastUpdate = DateTime.Now;

                    // Raise event on main thread
                    await MainThread.InvokeOnMainThreadAsync(() =>
                    {
                        BboReceived?.Invoke(this, bbo);
                    });
                }
            }
            catch (JsonException ex)
            {
                await MainThread.InvokeOnMainThreadAsync(() =>
                {
                    ErrorOccurred?.Invoke(this, $"JSON parse error: {ex.Message}");
                });
            }
            catch (Exception ex)
            {
                await MainThread.InvokeOnMainThreadAsync(() =>
                {
                    ErrorOccurred?.Invoke(this, $"Error processing message: {ex.Message}");
                });
            }
        }

        public void Dispose()
        {
            Stop();
            _mqttClient?.Dispose();
        }

        private static bool CheckNetworkConnection()
        {
            IEnumerable<ConnectionProfile> profiles = Connectivity.Current.ConnectionProfiles;


            if (Connectivity.Current.NetworkAccess == NetworkAccess.ConstrainedInternet)
            {
                Console.WriteLine("Internet access is available but is limited.");
                return true;
            }
            else if (Connectivity.Current.NetworkAccess != NetworkAccess.Internet)
            {
                Console.WriteLine("Internet access has been lost.");
                return false;
            }


            // Log each active connection
            Console.Write("Connections active: ");

            foreach (var item in profiles)
            {
                switch (item)
                {
                    case ConnectionProfile.Bluetooth:
                        Console.Write("Bluetooth");

                        Console.WriteLine();
                        break;
                    case ConnectionProfile.Cellular:
                        Console.Write("Cell");
                        Console.WriteLine();
                        break;
                    case ConnectionProfile.Ethernet:
                        Console.Write("Ethernet");
                        Console.WriteLine();
                        break;
                    case ConnectionProfile.WiFi:
                        Console.Write("WiFi");
                        Console.WriteLine();
                        break;
                    default:
                        break;
                }
            }

            Console.WriteLine();

            if (profiles.Contains(ConnectionProfile.WiFi))
            {
                return true;
            }
            if (profiles.Contains(ConnectionProfile.Ethernet))
            {
                return true;
            }
            return false;
        }
    }
}
