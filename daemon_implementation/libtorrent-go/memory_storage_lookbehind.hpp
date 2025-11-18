// ============================================================================
// LOOKBEHIND BUFFER IMPLEMENTATION FOR LIBTORRENT-GO
// ============================================================================
//
// INTEGRATION: Add these methods to the memory_storage class in memory_storage.hpp
//
// 1. Add to public section of memory_storage class
// 2. Add m_lookbehind_pieces member to private section
//
// ============================================================================

// ----------------------------------------------------------------------------
// PUBLIC METHODS - Add to memory_storage class public section
// ----------------------------------------------------------------------------

public:
    /**
     * Set pieces to protect from eviction for lookbehind buffer.
     * These pieces will be marked as reserved and won't be evicted by trim().
     *
     * THREAD SAFETY: Call from libtorrent's disk thread context.
     * Uses libtorrent's internal synchronization - no additional mutex needed.
     *
     * @param pieces Vector of piece indices to protect
     */
    void set_lookbehind_pieces(std::vector<int> const& pieces) {
        // Clear previous lookbehind reservations from reserved_pieces
        for (int i = 0; i < m_num_pieces && i < static_cast<int>(m_lookbehind_pieces.size()); i++) {
            if (m_lookbehind_pieces.get_bit(i)) {
                m_reserved_pieces.clear_bit(i);
            }
        }
        m_lookbehind_pieces.clear();

        if (pieces.empty()) {
            return;
        }

        // Find max piece index for resizing
        int max_piece = 0;
        for (int p : pieces) {
            if (p > max_piece) max_piece = p;
        }

        // Resize bitfield if needed
        if (max_piece >= static_cast<int>(m_lookbehind_pieces.size())) {
            m_lookbehind_pieces.resize(max_piece + 1, false);
        }

        // Set new lookbehind pieces as reserved
        for (int piece : pieces) {
            if (piece >= 0 && piece < m_num_pieces) {
                m_lookbehind_pieces.set_bit(piece);
                m_reserved_pieces.set_bit(piece);
            }
        }
    }

    /**
     * Clear all lookbehind reservations.
     * Call when stopping playback or switching files.
     */
    void clear_lookbehind() {
        for (int i = 0; i < m_num_pieces && i < static_cast<int>(m_lookbehind_pieces.size()); i++) {
            if (m_lookbehind_pieces.get_bit(i)) {
                m_reserved_pieces.clear_bit(i);
            }
        }
        m_lookbehind_pieces.clear();
    }

    /**
     * Check if a specific piece is in lookbehind AND available in memory.
     * Use this to verify data is actually cached before reporting fast-path availability.
     *
     * @param piece Piece index to check
     * @return true if piece is protected AND has data in memory
     */
    bool is_lookbehind_available(int piece) const {
        if (piece < 0 || piece >= m_num_pieces) {
            return false;
        }
        if (piece >= static_cast<int>(m_lookbehind_pieces.size()) ||
            !m_lookbehind_pieces.get_bit(piece)) {
            return false;
        }
        // Verify piece is actually in memory (has buffer assigned)
        return m_pieces[piece].bi >= 0;
    }

    /**
     * Get count of lookbehind pieces that are actually available in memory.
     * Useful for monitoring and debugging.
     *
     * @return Number of protected pieces with data
     */
    int get_lookbehind_available_count() const {
        int count = 0;
        int max_check = std::min(m_num_pieces, static_cast<int>(m_lookbehind_pieces.size()));
        for (int i = 0; i < max_check; i++) {
            if (m_lookbehind_pieces.get_bit(i) && m_pieces[i].bi >= 0) {
                count++;
            }
        }
        return count;
    }

    /**
     * Get total count of protected lookbehind pieces (may not all be in memory).
     *
     * @return Number of pieces marked for lookbehind protection
     */
    int get_lookbehind_protected_count() const {
        return static_cast<int>(m_lookbehind_pieces.count());
    }

    /**
     * Get memory used by available lookbehind pieces in bytes.
     *
     * @return Bytes of lookbehind data currently in memory
     */
    int64_t get_lookbehind_memory_used() const {
        return static_cast<int64_t>(get_lookbehind_available_count()) * m_piece_length;
    }

// ----------------------------------------------------------------------------
// PRIVATE MEMBER - Add to memory_storage class private section
// ----------------------------------------------------------------------------

private:
    lt::bitfield m_lookbehind_pieces;  // Track which pieces are for lookbehind


// ============================================================================
// C WRAPPER FUNCTIONS - Add to extern "C" section or new file
// ============================================================================

extern "C" {

void memory_storage_set_lookbehind_pieces(void* ms, int* pieces, int count) {
    if (ms == nullptr) return;

    std::vector<int> piece_vec;
    if (pieces != nullptr && count > 0) {
        piece_vec.assign(pieces, pieces + count);
    }

    static_cast<memory_storage*>(ms)->set_lookbehind_pieces(piece_vec);
}

void memory_storage_clear_lookbehind(void* ms) {
    if (ms == nullptr) return;
    static_cast<memory_storage*>(ms)->clear_lookbehind();
}

int memory_storage_is_lookbehind_available(void* ms, int piece) {
    if (ms == nullptr) return 0;
    return static_cast<memory_storage*>(ms)->is_lookbehind_available(piece) ? 1 : 0;
}

int memory_storage_get_lookbehind_available_count(void* ms) {
    if (ms == nullptr) return 0;
    return static_cast<memory_storage*>(ms)->get_lookbehind_available_count();
}

int memory_storage_get_lookbehind_protected_count(void* ms) {
    if (ms == nullptr) return 0;
    return static_cast<memory_storage*>(ms)->get_lookbehind_protected_count();
}

long long memory_storage_get_lookbehind_memory_used(void* ms) {
    if (ms == nullptr) return 0;
    return static_cast<memory_storage*>(ms)->get_lookbehind_memory_used();
}

} // extern "C"
