/**
 * Simple in-memory cache with TTL (Time To Live) support
 * Stores API responses to reduce unnecessary network requests
 */

class Cache {
  constructor() {
    this.cache = new Map();
    this.timestamps = new Map();
  }

  /**
   * Get cached value if it exists and hasn't expired
   * @param {string} key - Cache key
   * @param {number} ttl - Time to live in milliseconds (default: 5 minutes)
   * @returns {any|null} Cached value or null if expired/not found
   */
  get(key, ttl = 5 * 60 * 1000) {
    if (!this.cache.has(key)) {
      return null;
    }

    const timestamp = this.timestamps.get(key);
    const now = Date.now();

    // Check if cache has expired
    if (now - timestamp > ttl) {
      this.delete(key);
      return null;
    }

    return this.cache.get(key);
  }

  /**
   * Set cache value with current timestamp
   * @param {string} key - Cache key
   * @param {any} value - Value to cache
   */
  set(key, value) {
    this.cache.set(key, value);
    this.timestamps.set(key, Date.now());
  }

  /**
   * Delete specific cache entry
   * @param {string} key - Cache key
   */
  delete(key) {
    this.cache.delete(key);
    this.timestamps.delete(key);
  }

  /**
   * Clear all cache entries
   */
  clear() {
    this.cache.clear();
    this.timestamps.clear();
  }

  /**
   * Clear cache entries matching a pattern
   * @param {string|RegExp} pattern - Pattern to match keys against
   */
  clearPattern(pattern) {
    const regex = pattern instanceof RegExp ? pattern : new RegExp(pattern);
    for (const key of this.cache.keys()) {
      if (regex.test(key)) {
        this.delete(key);
      }
    }
  }

  /**
   * Get cache size
   * @returns {number} Number of cached entries
   */
  size() {
    return this.cache.size;
  }
}

// Export singleton instance
export const apiCache = new Cache();

/**
 * Higher-order function to wrap API calls with caching
 * @param {Function} apiCall - The API function to wrap
 * @param {Function} getCacheKey - Function to generate cache key from arguments
 * @param {number} ttl - Cache TTL in milliseconds
 */
export const withCache = (apiCall, getCacheKey, ttl = 5 * 60 * 1000) => {
  return async (...args) => {
    const cacheKey = getCacheKey(...args);
    
    // Try to get from cache first
    const cached = apiCache.get(cacheKey, ttl);
    if (cached !== null) {
      console.log(`[Cache HIT] ${cacheKey}`);
      return cached;
    }

    // Cache miss - make API call
    console.log(`[Cache MISS] ${cacheKey}`);
    const result = await apiCall(...args);
    
    // Store in cache
    apiCache.set(cacheKey, result);
    
    return result;
  };
};

/**
 * Cache key generators for common API patterns
 */
export const cacheKeys = {
  documents: (patientId) => patientId ? `documents:patient:${patientId}` : 'documents:me',
  document: (docId) => `document:${docId}`,
  patients: () => 'patients:all',
  linkedDoctors: () => 'linked-doctors',
  sharedDoctors: (docId) => `shared-doctors:${docId}`,
};

/**
 * Cache invalidation helpers
 */
export const invalidateCache = {
  // Invalidate all document-related caches
  documents: () => {
    apiCache.clearPattern(/^documents:/);
    apiCache.clearPattern(/^document:/);
  },
  
  // Invalidate specific document cache
  document: (docId) => {
    apiCache.delete(cacheKeys.document(docId));
    apiCache.clearPattern(/^documents:/);
  },
  
  // Invalidate patient-related caches
  patients: () => {
    apiCache.clearPattern(/^patients:/);
  },
  
  // Invalidate doctor connections
  linkedDoctors: () => {
    apiCache.delete(cacheKeys.linkedDoctors());
  },

  // Invalidate on logout
  all: () => {
    apiCache.clear();
  }
};

export default apiCache;
