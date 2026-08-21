// A TRIMMED librclone for iOS.
//
// rclone's own librclone package is not usable here. It imports cmd/mount,
// cmd/cmount and cmd/mount2, and while all three fall to rclone's *_unsupported
// stubs on ios/arm64, cmd/mount2's build tag is `linux || (darwin && amd64)` -
// which the x86_64 SIMULATOR satisfies, dragging in go-fuse and cobra.
//
// So this re-exports the same C ABI over rclone's INNER librclone package,
// importing only what Airclone actually calls.
//
// fs/sync is NOT optional. rclone's own gomobile binding omits it, and
// state/transfer_service.dart dispatches sync/copy and sync/move - taking that
// binding verbatim would silently lose every directory transfer.
//
// The ABI is byte-for-byte what rclone/librclone/librclone.go exports, so
// app/lib/src/rclone/librclone_ffi.dart needs no change to its signatures.
package main

/*
#include <stdlib.h>

struct RcloneRPCResult {
	char* Output;
	int   Status;
};
*/
import "C"

import (
	"unsafe"

	_ "github.com/rclone/rclone/backend/all" // every storage backend
	_ "github.com/rclone/rclone/fs/operations"
	_ "github.com/rclone/rclone/fs/sync" // sync/copy + sync/move - see above
	"github.com/rclone/rclone/librclone/librclone"
)

//export RcloneInitialize
func RcloneInitialize() { librclone.Initialize() }

//export RcloneFinalize
func RcloneFinalize() { librclone.Finalize() }

//export RcloneRPC
func RcloneRPC(method *C.char, input *C.char) C.struct_RcloneRPCResult {
	out, status := librclone.RPC(C.GoString(method), C.GoString(input))
	return C.struct_RcloneRPCResult{
		Output: C.CString(out),
		Status: C.int(status),
	}
}

//export RcloneFreeString
func RcloneFreeString(s *C.char) { C.free(unsafe.Pointer(s)) }

func main() {}
