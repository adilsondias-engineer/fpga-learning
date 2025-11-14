package au.com.apiled.apps.network;

import com.google.gson.Gson;
import au.com.apiled.apps.dto.BboUpdate;

import java.io.*;
import java.net.Socket;
import java.net.SocketException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * TCP Client for connecting to the BBO Gateway on port 9999 (configurable).
 * Listens for JSON-formatted BBO updates and notifies registered listeners.
 *
 * Connection details:
 * - Host: localhost (default, configurable)
 * - Port: 9999 (default, configurable)
 * - Protocol: TCP with JSON messages
 * - One JSON object per line (newline-delimited)
 */
public class BboTcpClient {
    private static final Logger LOGGER = Logger.getLogger(BboTcpClient.class.getName());
    private static final int DEFAULT_PORT = 9999;
    private static final String DEFAULT_HOST = "localhost";

    private final String host;
    private final int port;
    private Socket socket;
    private BufferedReader reader;
    private PrintWriter writer;
    private boolean connected = false;
    private boolean running = false;
    private Thread listenerThread;
    private final Gson gson;
    private final List<BboUpdateListener> listeners;

    /**
     * Listener interface for BBO update events.
     */
    public interface BboUpdateListener {
        void onBboUpdate(BboUpdate bbo);

        void onConnectionStateChanged(boolean connected);

        void onError(String errorMessage);
    }

    // Constructors
    public BboTcpClient() {
        this(DEFAULT_HOST, DEFAULT_PORT);
    }

    public BboTcpClient(String host, int port) {
        this.host = host;
        this.port = port;
        this.gson = new Gson();
        this.listeners = new CopyOnWriteArrayList<>();
    }

    /**
     * Connect to the TCP gateway.
     * Starts a listener thread to receive BBO updates.
     */
    public synchronized void connect() {
        if (connected) {
            LOGGER.warning("Already connected to " + host + ":" + port);
            return;
        }

        try {
            LOGGER.info("Connecting to " + host + ":" + port);
            socket = new Socket(host, port);
            reader = new BufferedReader(new InputStreamReader(socket.getInputStream()));
            writer = new PrintWriter(socket.getOutputStream(), true);
            connected = true;
            running = true;

            // Start listener thread
            listenerThread = new Thread(this::listenForUpdates, "BBO-TCP-Listener");
            listenerThread.setDaemon(true);
            listenerThread.start();

            notifyConnectionStateChanged(true);
            LOGGER.info("Connected successfully to " + host + ":" + port);
        } catch (IOException e) {
            connected = false;
            LOGGER.log(Level.SEVERE, "Failed to connect to " + host + ":" + port, e);
            notifyError("Connection failed: " + e.getMessage());
        }
    }

    /**
     * Disconnect from the TCP gateway.
     */
    public synchronized void disconnect() {
        if (!connected) {
            return;
        }

        try {
            running = false;
            connected = false;

            if (reader != null) {
                reader.close();
            }
            if (writer != null) {
                writer.close();
            }
            if (socket != null && !socket.isClosed()) {
                socket.close();
            }

            if (listenerThread != null) {
                listenerThread.join(5000);
            }

            notifyConnectionStateChanged(false);
            LOGGER.info("Disconnected from " + host + ":" + port);
        } catch (IOException | InterruptedException e) {
            LOGGER.log(Level.SEVERE, "Error during disconnect", e);
        }
    }

    /**
     * Main listener loop that reads JSON lines from the TCP stream.
     * Each line should contain a complete JSON BBO object.
     */
    private void listenForUpdates() {
        try {
            String line;
            while (running && (line = reader.readLine()) != null) {
                try {
                    // Parse JSON string to BboUpdate object
                    BboUpdate bbo = gson.fromJson(line, BboUpdate.class);
                    notifyBboUpdate(bbo);
                } catch (com.google.gson.JsonSyntaxException e) {
                    LOGGER.log(Level.WARNING, "Invalid JSON received: " + line, e);
                    notifyError("Invalid JSON: " + e.getMessage());
                }
            }
        } catch (SocketException e) {
            if (running) {
                LOGGER.log(Level.INFO, "Socket exception (may be expected during disconnect)", e);
            }
        } catch (IOException e) {
            if (running) {
                LOGGER.log(Level.SEVERE, "IO error while listening for updates", e);
                notifyError("IO error: " + e.getMessage());
            }
        } finally {
            connected = false;
            notifyConnectionStateChanged(false);
            LOGGER.info("Listener thread terminated");
        }
    }

    /**
     * Send a command to the gateway (if needed for control messages).
     */
    public void sendCommand(String command) {
        if (!connected || writer == null) {
            LOGGER.warning("Not connected, cannot send command: " + command);
            return;
        }
        writer.println(command);
    }

    /**
     * Check if currently connected.
     */
    public boolean isConnected() {
        return connected;
    }

    /**
     * Register a listener for BBO updates.
     */
    public void addListener(BboUpdateListener listener) {
        listeners.add(listener);
        LOGGER.info("Listener registered. Total listeners: " + listeners.size());
    }

    /**
     * Unregister a listener.
     */
    public void removeListener(BboUpdateListener listener) {
        listeners.remove(listener);
        LOGGER.info("Listener unregistered. Total listeners: " + listeners.size());
    }

    /**
     * Notify all listeners of a BBO update.
     */
    private void notifyBboUpdate(BboUpdate bbo) {
        for (BboUpdateListener listener : listeners) {
            try {
                listener.onBboUpdate(bbo);
            } catch (Exception e) {
                LOGGER.log(Level.WARNING, "Error notifying listener", e);
            }
        }
    }

    /**
     * Notify all listeners of connection state change.
     */
    private void notifyConnectionStateChanged(boolean connected) {
        for (BboUpdateListener listener : listeners) {
            try {
                listener.onConnectionStateChanged(connected);
            } catch (Exception e) {
                LOGGER.log(Level.WARNING, "Error notifying listener of connection change", e);
            }
        }
    }

    /**
     * Notify all listeners of an error.
     */
    private void notifyError(String errorMessage) {
        for (BboUpdateListener listener : listeners) {
            try {
                listener.onError(errorMessage);
            } catch (Exception e) {
                LOGGER.log(Level.WARNING, "Error notifying listener of error", e);
            }
        }
    }

    public String getHost() {
        return host;
    }

    public int getPort() {
        return port;
    }

    public List<BboUpdateListener> getListeners() {
        return new ArrayList<>(listeners);
    }
}
