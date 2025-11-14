package au.com.apiled.apps.data;

import au.com.apiled.apps.dto.BboUpdate;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.logging.Logger;

/**
 * Central data store for managing BBO updates from the gateway.
 * Maintains the latest BBO for each symbol and historical data for charting.
 *
 * Features:
 * - Thread-safe storage for current BBO per symbol
 * - Historical data buffer for time-series charting
 * - Observable for UI updates
 */
public class BboDataStore {
    private static final Logger LOGGER = Logger.getLogger(BboDataStore.class.getName());
    private static final int MAX_HISTORY_SIZE = 1000; // Max data points per symbol

    // Current BBO for each symbol
    private final Map<String, BboUpdate> currentBbo;

    // Historical data for charting (timestamp-indexed)
    private final Map<String, LinkedList<BboUpdate>> bboHistory;

    // UI update callbacks
    private final List<BboDataStoreListener> listeners;

    /**
     * Listener interface for data store changes.
     */
    public interface BboDataStoreListener {
        void onBboUpdated(BboUpdate bbo);

        void onBboHistoryUpdated(String symbol, LinkedList<BboUpdate> history);
    }

    public BboDataStore() {
        this.currentBbo = new ConcurrentHashMap<>();
        this.bboHistory = new ConcurrentHashMap<>();
        this.listeners = Collections.synchronizedList(new ArrayList<>());
    }

    /**
     * Update the BBO for a symbol and maintain history.
     */
    public void updateBbo(BboUpdate bbo) {
        if (bbo == null || bbo.getSymbol() == null) {
            LOGGER.warning("Invalid BBO update (null or missing symbol)");
            return;
        }

        String symbol = bbo.getSymbol();

        // Store current BBO
        currentBbo.put(symbol, bbo);

        // Add to history
        bboHistory.computeIfAbsent(symbol, k -> new LinkedList<>()).add(bbo);

        // Trim history if it exceeds max size
        LinkedList<BboUpdate> history = bboHistory.get(symbol);
        if (history.size() > MAX_HISTORY_SIZE) {
            history.removeFirst();
        }

        // Notify listeners
        notifyBboUpdated(bbo);
        notifyHistoryUpdated(symbol, new LinkedList<>(history));
    }

    /**
     * Get the current BBO for a symbol.
     */
    public BboUpdate getCurrentBbo(String symbol) {
        return currentBbo.get(symbol);
    }

    /**
     * Get all current BBOs.
     */
    public Collection<BboUpdate> getAllCurrentBbos() {
        return new ArrayList<>(currentBbo.values());
    }

    /**
     * Get historical BBO data for a symbol (for charting).
     */
    public LinkedList<BboUpdate> getHistory(String symbol) {
        LinkedList<BboUpdate> history = bboHistory.get(symbol);
        return history != null ? new LinkedList<>(history) : new LinkedList<>();
    }

    /**
     * Get all symbols with available BBO data.
     */
    public Set<String> getAvailableSymbols() {
        return new HashSet<>(currentBbo.keySet());
    }

    /**
     * Clear all data (useful for testing or reset).
     */
    public void clear() {
        currentBbo.clear();
        bboHistory.clear();
        LOGGER.info("Data store cleared");
    }

    /**
     * Get current size of BBO data (number of symbols).
     */
    public int size() {
        return currentBbo.size();
    }

    /**
     * Register a listener for data store changes.
     */
    public void addListener(BboDataStoreListener listener) {
        listeners.add(listener);
        LOGGER.info("Data store listener registered. Total: " + listeners.size());
    }

    /**
     * Unregister a listener.
     */
    public void removeListener(BboDataStoreListener listener) {
        listeners.remove(listener);
    }

    /**
     * Get spread statistics across all symbols.
     */
    public SpreadStatistics getSpreadStatistics() {
        Collection<BboUpdate> bbos = getAllCurrentBbos();
        if (bbos.isEmpty()) {
            return new SpreadStatistics(0, 0, 0, 0);
        }

        double minSpread = Double.MAX_VALUE;
        double maxSpread = 0;
        double totalSpreadPct = 0;
        int count = 0;

        for (BboUpdate bbo : bbos) {
            if (bbo.getSpread() > 0) {
                minSpread = Math.min(minSpread, bbo.getSpread());
                maxSpread = Math.max(maxSpread, bbo.getSpread());
                totalSpreadPct += bbo.getSpreadPct();
                count++;
            }
        }

        double avgSpreadPct = count > 0 ? totalSpreadPct / count : 0;
        return new SpreadStatistics(minSpread, maxSpread, avgSpreadPct, count);
    }

    /**
     * Data class for spread statistics.
     */
    public record SpreadStatistics(
            double minSpread,
            double maxSpread,
            double avgSpreadPct,
            int symbolCount) {
        @Override
        public String toString() {
            return String.format(
                    "SpreadStats{min=%.4f, max=%.4f, avgPct=%.2f%%, symbols=%d}",
                    minSpread, maxSpread, avgSpreadPct, symbolCount);
        }
    }

    private void notifyBboUpdated(BboUpdate bbo) {
        for (BboDataStoreListener listener : listeners) {
            try {
                listener.onBboUpdated(bbo);
            } catch (Exception e) {
                LOGGER.warning("Error notifying listener of BBO update: " + e.getMessage());
            }
        }
    }

    private void notifyHistoryUpdated(String symbol, LinkedList<BboUpdate> history) {
        for (BboDataStoreListener listener : listeners) {
            try {
                listener.onBboHistoryUpdated(symbol, history);
            } catch (Exception e) {
                LOGGER.warning("Error notifying listener of history update: " + e.getMessage());
            }
        }
    }
}
