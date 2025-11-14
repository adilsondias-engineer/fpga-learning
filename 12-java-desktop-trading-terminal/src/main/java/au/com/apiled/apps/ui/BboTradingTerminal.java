package au.com.apiled.apps.ui;

import javafx.application.Application;
import javafx.application.Platform;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
import javafx.geometry.Insets;
import javafx.scene.Scene;
import javafx.scene.chart.LineChart;
import javafx.scene.chart.NumberAxis;
import javafx.scene.chart.XYChart;
import javafx.scene.control.*;
import javafx.scene.layout.BorderPane;
import javafx.scene.layout.HBox;
import javafx.scene.layout.VBox;
import javafx.stage.Stage;
import au.com.apiled.apps.data.BboDataStore;
import au.com.apiled.apps.dto.BboUpdate;
import au.com.apiled.apps.network.BboTcpClient;

import java.util.*;
import java.util.logging.Logger;

/**
 * JavaFX Trading Terminal for real-time BBO (Best Bid Offer) visualization.
 *
 * Features:
 * - Real-time BBO table showing all symbols
 * - Spread chart for time-series visualization
 * - Connection status indicator
 * - Configurable TCP host and port
 *
 * Usage:
 * 1. Configure host/port (default localhost:9999)
 * 2. Click "Connect" to establish TCP connection
 * 3. BBO updates will appear in the table and chart
 */
public class BboTradingTerminal extends Application {
    private static final Logger LOGGER = Logger.getLogger(BboTradingTerminal.class.getName());
    private static final int WINDOW_WIDTH = 1200;
    private static final int WINDOW_HEIGHT = 800;

    // Model
    private BboDataStore dataStore;
    private BboTcpClient tcpClient;

    // UI Components
    private TableView<BboUpdate> bboTable;
    private ObservableList<BboUpdate> bboTableData;
    private LineChart<Number, Number> spreadChart;
    private Label connectionStatus;
    private TextField hostTextField;
    private TextField portTextField;
    private Button connectButton;
    private Button disconnectButton;

    // Chart data series (one per symbol)
    private final Map<String, XYChart.Series<Number, Number>> chartSeries = new HashMap<>();

    @Override
    public void start(Stage primaryStage) {
        try {
            // Initialize models
            dataStore = new BboDataStore();
            tcpClient = new BboTcpClient();

            // Create UI
            BorderPane root = createMainLayout();
            Scene scene = new Scene(root, WINDOW_WIDTH, WINDOW_HEIGHT);

            primaryStage.setTitle("BBO Trading Terminal - FPGA Gateway Monitor");
            primaryStage.setScene(scene);
            primaryStage.setOnCloseRequest(e -> shutdown());
            primaryStage.show();

            // Initialize data flow
            setupDataFlow();

            LOGGER.info("Trading Terminal started");
        } catch (Exception e) {
            LOGGER.severe("Failed to start application: " + e.getMessage());
            e.printStackTrace();
        }
    }

    /**
     * Create the main layout with table, chart, and controls.
     */
    private BorderPane createMainLayout() {
        BorderPane root = new BorderPane();

        // Top: Control panel
        root.setTop(createControlPanel());

        // Center: Split between table and chart
        SplitPane centerSplit = new SplitPane();
        centerSplit.setDividerPositions(0.4);

        // Left: BBO Table
        VBox tablePane = new VBox();
        tablePane.setPadding(new Insets(10));
        tablePane.setSpacing(10);
        tablePane.getChildren().add(new Label("BBO Updates"));
        tablePane.getChildren().add(createBboTable());
        centerSplit.getItems().add(tablePane);

        // Right: Spread Chart
        VBox chartPane = new VBox();
        chartPane.setPadding(new Insets(10));
        chartPane.setSpacing(10);
        chartPane.getChildren().add(new Label("Spread Over Time"));
        chartPane.getChildren().add(createSpreadChart());
        VBox.setVgrow(spreadChart, javafx.scene.layout.Priority.ALWAYS);
        centerSplit.getItems().add(chartPane);

        root.setCenter(centerSplit);

        // Bottom: Status bar
        root.setBottom(createStatusBar());

        return root;
    }

    /**
     * Create control panel with connection options.
     */
    private HBox createControlPanel() {
        HBox controlPanel = new HBox();
        controlPanel.setPadding(new Insets(10));
        controlPanel.setSpacing(10);
        controlPanel.setStyle("-fx-border-color: #cccccc; -fx-border-width: 0 0 1 0;");

        Label hostLabel = new Label("Host:");
        hostTextField = new TextField("localhost");
        hostTextField.setPrefWidth(120);

        Label portLabel = new Label("Port:");
        portTextField = new TextField("9999");
        portTextField.setPrefWidth(80);

        connectButton = new Button("Connect");
        connectButton.setStyle("-fx-padding: 5 15 5 15; -fx-font-size: 12;");
        connectButton.setOnAction(e -> handleConnect());

        disconnectButton = new Button("Disconnect");
        disconnectButton.setStyle("-fx-padding: 5 15 5 15; -fx-font-size: 12;");
        disconnectButton.setDisable(true);
        disconnectButton.setOnAction(e -> handleDisconnect());

        Label statsLabel = new Label("Stats:");
        connectionStatus = new Label("● Disconnected");
        connectionStatus.setStyle("-fx-text-fill: red; -fx-font-size: 12; -fx-font-weight: bold;");

        Separator separator = new Separator();
        separator.setStyle("-fx-padding: 0 10 0 10;");

        controlPanel.getChildren().addAll(
                hostLabel, hostTextField,
                portLabel, portTextField,
                connectButton, disconnectButton,
                separator,
                statsLabel, connectionStatus);

        return controlPanel;
    }

    /**
     * Create BBO data table showing current prices.
     */
    private TableView<BboUpdate> createBboTable() {
        bboTable = new TableView<>();
        bboTableData = FXCollections.observableArrayList();
        bboTable.setItems(bboTableData);

        // Symbol column
        TableColumn<BboUpdate, String> symbolCol = new TableColumn<>("Symbol");
        symbolCol.setCellValueFactory(
                cellData -> new javafx.beans.property.SimpleStringProperty(cellData.getValue().getSymbol()));
        symbolCol.setPrefWidth(80);

        // Bid Price column
        TableColumn<BboUpdate, String> bidPriceCol = new TableColumn<>("Bid Price");
        bidPriceCol.setCellValueFactory(cellData -> {
            double price = cellData.getValue().getBid() != null ? cellData.getValue().getBid().getPrice() : 0;
            return new javafx.beans.property.SimpleStringProperty(String.format("%.2f", price));
        });
        bidPriceCol.setPrefWidth(100);

        // Bid Shares column
        TableColumn<BboUpdate, String> bidSharesCol = new TableColumn<>("Bid Shares");
        bidSharesCol.setCellValueFactory(cellData -> {
            long shares = cellData.getValue().getBid() != null ? cellData.getValue().getBid().getShares() : 0;
            return new javafx.beans.property.SimpleStringProperty(String.valueOf(shares));
        });
        bidSharesCol.setPrefWidth(100);

        // Ask Price column
        TableColumn<BboUpdate, String> askPriceCol = new TableColumn<>("Ask Price");
        askPriceCol.setCellValueFactory(cellData -> {
            double price = cellData.getValue().getAsk() != null ? cellData.getValue().getAsk().getPrice() : 0;
            return new javafx.beans.property.SimpleStringProperty(String.format("%.2f", price));
        });
        askPriceCol.setPrefWidth(100);

        // Ask Shares column
        TableColumn<BboUpdate, String> askSharesCol = new TableColumn<>("Ask Shares");
        askSharesCol.setCellValueFactory(cellData -> {
            long shares = cellData.getValue().getAsk() != null ? cellData.getValue().getAsk().getShares() : 0;
            return new javafx.beans.property.SimpleStringProperty(String.valueOf(shares));
        });
        askSharesCol.setPrefWidth(100);

        // Spread column
        TableColumn<BboUpdate, String> spreadCol = new TableColumn<>("Spread");
        spreadCol.setCellValueFactory(cellData -> {
            double spread = cellData.getValue().getSpread();
            return new javafx.beans.property.SimpleStringProperty(String.format("%.4f", spread));
        });
        spreadCol.setPrefWidth(80);

        // Spread % column
        TableColumn<BboUpdate, String> spreadPctCol = new TableColumn<>("Spread %");
        spreadPctCol.setCellValueFactory(cellData -> {
            double spreadPct = cellData.getValue().getSpreadPct();
            return new javafx.beans.property.SimpleStringProperty(String.format("%.2f%%", spreadPct));
        });
        spreadPctCol.setPrefWidth(80);

        bboTable.getColumns().addAll(
                Arrays.asList(
                        symbolCol, bidPriceCol, bidSharesCol, askPriceCol, askSharesCol, spreadCol, spreadPctCol));

        return bboTable;
    }

    /**
     * Create spread chart for time-series visualization.
     */
    private LineChart<Number, Number> createSpreadChart() {
        NumberAxis xAxis = new NumberAxis();
        xAxis.setLabel("Time");
        xAxis.setForceZeroInRange(false);

        NumberAxis yAxis = new NumberAxis();
        yAxis.setLabel("Spread ($)");

        spreadChart = new LineChart<>(xAxis, yAxis);
        spreadChart.setTitle("Spread Over Time");
        spreadChart.setCreateSymbols(false);
        spreadChart.setAnimated(false);

        return spreadChart;
    }

    /**
     * Create status bar showing connection info and statistics.
     */
    private HBox createStatusBar() {
        HBox statusBar = new HBox();
        statusBar.setPadding(new Insets(10));
        statusBar.setSpacing(20);
        statusBar.setStyle("-fx-border-color: #cccccc; -fx-border-width: 1 0 0 0; -fx-background-color: #f5f5f5;");

        Label symbolCountLabel = new Label("Symbols: 0");
        Label spreadStatsLabel = new Label("Spread: Min=-, Max=-, Avg=-");

        statusBar.getChildren().addAll(symbolCountLabel, spreadStatsLabel);

        // Update status periodically
        new Timer().scheduleAtFixedRate(new TimerTask() {
            @Override
            public void run() {
                Platform.runLater(() -> {
                    Set<String> symbols = dataStore.getAvailableSymbols();
                    symbolCountLabel.setText("Symbols: " + symbols.size());

                    BboDataStore.SpreadStatistics stats = dataStore.getSpreadStatistics();
                    spreadStatsLabel.setText(String.format(
                            "Spread: Min=%.4f, Max=%.4f, Avg=%.2f%%",
                            stats.minSpread(), stats.maxSpread(), stats.avgSpreadPct()));
                });
            }
        }, 1000, 1000);

        return statusBar;
    }

    /**
     * Setup data flow: TCP client → Data store → UI updates.
     */
    private void setupDataFlow() {
        // Listen to data store updates
        dataStore.addListener(new BboDataStore.BboDataStoreListener() {
            @Override
            public void onBboUpdated(BboUpdate bbo) {
                // Update table
                Platform.runLater(() -> {
                    bboTableData.removeIf(b -> b.getSymbol().equals(bbo.getSymbol()));
                    bboTableData.add(bbo);
                });
            }

            @Override
            public void onBboHistoryUpdated(String symbol, LinkedList<BboUpdate> history) {
                // Update chart
                Platform.runLater(() -> updateChart(symbol, history));
            }
        });

        // Listen to TCP client events
        tcpClient.addListener(new BboTcpClient.BboUpdateListener() {
            @Override
            public void onBboUpdate(BboUpdate bbo) {
                // Store in data store (which will notify listeners)
                dataStore.updateBbo(bbo);
            }

            @Override
            public void onConnectionStateChanged(boolean connected) {
                Platform.runLater(() -> updateConnectionStatus(connected));
            }

            @Override
            public void onError(String errorMessage) {
                Platform.runLater(() -> {
                    LOGGER.warning("TCP Error: " + errorMessage);
                    Alert alert = new Alert(Alert.AlertType.WARNING);
                    alert.setTitle("Connection Error");
                    alert.setContentText(errorMessage);
                    alert.show();
                });
            }
        });
    }

    /**
     * Update UI chart with historical data.
     */
    private void updateChart(String symbol, LinkedList<BboUpdate> history) {
        // Get or create series for symbol
        XYChart.Series<Number, Number> series = chartSeries.computeIfAbsent(symbol, k -> {
            XYChart.Series<Number, Number> newSeries = new XYChart.Series<>();
            newSeries.setName(symbol);
            spreadChart.getData().add(newSeries);
            return newSeries;
        });

        // Clear and rebuild series data (keep last 50 points)
        series.getData().clear();
        int startIdx = Math.max(0, history.size() - 50);
        for (int i = startIdx; i < history.size(); i++) {
            BboUpdate bbo = history.get(i);
            series.getData().add(new XYChart.Data<>(i, bbo.getSpread()));
        }
    }

    /**
     * Handle connect button click.
     */
    private void handleConnect() {
        String host = hostTextField.getText().trim();
        int port;

        try {
            port = Integer.parseInt(portTextField.getText().trim());
        } catch (NumberFormatException e) {
            Alert alert = new Alert(Alert.AlertType.ERROR);
            alert.setTitle("Invalid Port");
            alert.setContentText("Port must be a valid integer");
            alert.show();
            return;
        }

        tcpClient = new BboTcpClient(host, port);
        tcpClient.addListener(new BboTcpClient.BboUpdateListener() {
            @Override
            public void onBboUpdate(BboUpdate bbo) {
                dataStore.updateBbo(bbo);
            }

            @Override
            public void onConnectionStateChanged(boolean connected) {
                Platform.runLater(() -> updateConnectionStatus(connected));
            }

            @Override
            public void onError(String errorMessage) {
                Platform.runLater(() -> {
                    Alert alert = new Alert(Alert.AlertType.WARNING);
                    alert.setTitle("Connection Error");
                    alert.setContentText(errorMessage);
                    alert.show();
                });
            }
        });

        tcpClient.connect();
    }

    /**
     * Handle disconnect button click.
     */
    private void handleDisconnect() {
        tcpClient.disconnect();
    }

    /**
     * Update connection status display.
     */
    private void updateConnectionStatus(boolean connected) {
        if (connected) {
            connectionStatus.setText("● Connected");
            connectionStatus.setStyle("-fx-text-fill: green; -fx-font-size: 12; -fx-font-weight: bold;");
            connectButton.setDisable(true);
            disconnectButton.setDisable(false);
            hostTextField.setDisable(true);
            portTextField.setDisable(true);
        } else {
            connectionStatus.setText("● Disconnected");
            connectionStatus.setStyle("-fx-text-fill: red; -fx-font-size: 12; -fx-font-weight: bold;");
            connectButton.setDisable(false);
            disconnectButton.setDisable(true);
            hostTextField.setDisable(false);
            portTextField.setDisable(false);
        }
    }

    /**
     * Cleanup on application shutdown.
     */
    private void shutdown() {
        LOGGER.info("Shutting down Trading Terminal");
        if (tcpClient != null && tcpClient.isConnected()) {
            tcpClient.disconnect();
        }
    }

    public static void main(String[] args) {
        launch(args);
    }
}
