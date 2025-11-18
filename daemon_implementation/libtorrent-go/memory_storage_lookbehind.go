// Package libtorrent provides Go bindings for libtorrent-rasterbar
//
// INTEGRATION: Add these methods to your existing MemoryStorage type
//
package libtorrent

/*
#include <stdlib.h>

// Lookbehind C wrapper function declarations
void memory_storage_set_lookbehind_pieces(void* ms, int* pieces, int count);
void memory_storage_clear_lookbehind(void* ms);
int memory_storage_is_lookbehind_available(void* ms, int piece);
int memory_storage_get_lookbehind_available_count(void* ms);
int memory_storage_get_lookbehind_protected_count(void* ms);
long long memory_storage_get_lookbehind_memory_used(void* ms);
*/
import "C"
import (
	"unsafe"
)

// SetLookbehindPieces sets pieces to protect from eviction for backward seeking.
// Pass nil or empty slice to clear all lookbehind reservations.
func (ms MemoryStorage) SetLookbehindPieces(pieces []int) {
	if len(pieces) == 0 {
		C.memory_storage_clear_lookbehind(ms.swigCPtr)
		return
	}

	// Convert Go slice to C array
	cPieces := make([]C.int, len(pieces))
	for i, p := range pieces {
		cPieces[i] = C.int(p)
	}

	C.memory_storage_set_lookbehind_pieces(
		ms.swigCPtr,
		(*C.int)(unsafe.Pointer(&cPieces[0])),
		C.int(len(pieces)),
	)
}

// ClearLookbehind removes all lookbehind piece reservations.
func (ms MemoryStorage) ClearLookbehind() {
	C.memory_storage_clear_lookbehind(ms.swigCPtr)
}

// IsLookbehindAvailable checks if a piece is protected AND available in memory.
func (ms MemoryStorage) IsLookbehindAvailable(piece int) bool {
	return C.memory_storage_is_lookbehind_available(ms.swigCPtr, C.int(piece)) != 0
}

// GetLookbehindAvailableCount returns count of protected pieces actually in memory.
func (ms MemoryStorage) GetLookbehindAvailableCount() int {
	return int(C.memory_storage_get_lookbehind_available_count(ms.swigCPtr))
}

// GetLookbehindProtectedCount returns total count of protected pieces.
func (ms MemoryStorage) GetLookbehindProtectedCount() int {
	return int(C.memory_storage_get_lookbehind_protected_count(ms.swigCPtr))
}

// GetLookbehindMemoryUsed returns bytes used by lookbehind buffer.
func (ms MemoryStorage) GetLookbehindMemoryUsed() int64 {
	return int64(C.memory_storage_get_lookbehind_memory_used(ms.swigCPtr))
}
