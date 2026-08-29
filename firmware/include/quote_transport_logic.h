#pragma once

#include <cstdint>

enum QuoteMetadataTransport {
  QUOTE_METADATA_SERIAL,
  QUOTE_METADATA_HTTP,
};

struct QuoteBitmapFetchState {
  bool httpReachabilityConfirmed = false;
  uint8_t failureCount = 0;
  uint32_t retryAfterMs = 0;
};

struct QuoteMetadataPollInputs {
  bool wifiConnected = false;
  bool bridgeConfigured = false;
  bool modeNeedsQuote = false;
  bool intervalElapsed = false;
  bool wiredActive = false;
};

inline bool quoteTransportDeadlineReached(uint32_t nowMs, uint32_t deadlineMs) {
  return deadlineMs != 0 && static_cast<int32_t>(nowMs - deadlineMs) >= 0;
}

inline void noteQuoteHTTPReachable(QuoteBitmapFetchState &state) {
  state.httpReachabilityConfirmed = true;
}

inline void noteQuoteMetadataReceived(QuoteBitmapFetchState &state,
                                      QuoteMetadataTransport transport) {
  if (transport == QUOTE_METADATA_HTTP) noteQuoteHTTPReachable(state);
}

inline void noteQuoteHTTPMetadataFailure(QuoteBitmapFetchState &state) {
  state.httpReachabilityConfirmed = false;
}

inline bool quoteBitmapFetchAllowed(const QuoteBitmapFetchState &state, uint32_t nowMs) {
  return state.httpReachabilityConfirmed &&
         (state.retryAfterMs == 0 || quoteTransportDeadlineReached(nowMs, state.retryAfterMs));
}

inline uint32_t quoteBitmapBackoffMs(uint8_t failureCount) {
  uint32_t delayMs = 5000U;
  for (uint8_t failure = 1; failure < failureCount && delayMs < 60000U; ++failure) {
    delayMs *= 2U;
    if (delayMs > 60000U) delayMs = 60000U;
  }
  return delayMs;
}

inline void noteQuoteBitmapFetchFailure(QuoteBitmapFetchState &state, uint32_t nowMs) {
  if (state.failureCount < 5) ++state.failureCount;
  state.retryAfterMs = nowMs + quoteBitmapBackoffMs(state.failureCount);
}

inline void noteQuoteBitmapFetchSuccess(QuoteBitmapFetchState &state) {
  state.httpReachabilityConfirmed = true;
  state.failureCount = 0;
  state.retryAfterMs = 0;
}

inline void resetQuoteBitmapFetchState(QuoteBitmapFetchState &state) {
  state = QuoteBitmapFetchState{};
}

inline bool shouldPollQuoteMetadataHTTP(const QuoteMetadataPollInputs &input) {
  return input.wifiConnected && input.bridgeConfigured && input.modeNeedsQuote &&
         input.intervalElapsed && !input.wiredActive;
}
