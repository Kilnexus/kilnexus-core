const std = @import("std");

const Ed25519 = std.crypto.sign.Ed25519;
const Blake2b512 = std.crypto.hash.blake2.Blake2b512;

pub const zig_public_key_b64 = "RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U";

pub fn verifyFileSignature(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    signature_path: []const u8,
) !void {
    try verifyFileSignatureWithKey(allocator, file_path, signature_path, zig_public_key_b64);
}

pub fn verifyFileSignatureWithKey(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    signature_path: []const u8,
    public_key_b64: []const u8,
) !void {
    const pub_key = try parsePublicKey(allocator, public_key_b64);

    const sig_data = try readSmallFile(allocator, signature_path, 64 * 1024);
    defer allocator.free(sig_data);

    const sig_line = findSignatureLine(sig_data) orelse return error.MinisignInvalidSignatureFile;
    const signature = try parseSignatureLine(allocator, sig_line);

    if (!std.mem.eql(u8, &signature.key_id, &pub_key.key_id)) return error.MinisignKeyIdMismatch;

    const digest = try hashFile(file_path);

    const public_key = try Ed25519.PublicKey.fromBytes(pub_key.public_key);
    const sig = Ed25519.Signature.fromBytes(signature.sig);
    try sig.verify(&digest, public_key);
}

const PublicKey = struct {
    key_id: [8]u8,
    public_key: [32]u8,
};

const Signature = struct {
    key_id: [8]u8,
    sig: [64]u8,
};

fn parsePublicKey(allocator: std.mem.Allocator, b64: []const u8) !PublicKey {
    const decoded = try decodeBase64Alloc(allocator, b64);
    defer allocator.free(decoded);
    if (decoded.len != 42) return error.MinisignInvalidPublicKey;
    if (!std.mem.eql(u8, decoded[0..2], "Ed")) return error.MinisignInvalidPublicKey;

    var key_id: [8]u8 = undefined;
    @memcpy(&key_id, decoded[2..10]);
    var pk: [32]u8 = undefined;
    @memcpy(&pk, decoded[10..42]);

    return .{ .key_id = key_id, .public_key = pk };
}

fn parseSignatureLine(allocator: std.mem.Allocator, b64: []const u8) !Signature {
    const decoded = try decodeBase64Alloc(allocator, b64);
    defer allocator.free(decoded);
    if (decoded.len != 74) return error.MinisignInvalidSignature;
    if (!std.mem.eql(u8, decoded[0..2], "Ed")) return error.MinisignInvalidSignature;

    var key_id: [8]u8 = undefined;
    @memcpy(&key_id, decoded[2..10]);
    var sig: [64]u8 = undefined;
    @memcpy(&sig, decoded[10..74]);

    return .{ .key_id = key_id, .sig = sig };
}

fn findSignatureLine(data: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, data, '\n');
    var found: ?[]const u8 = null;
    while (it.next()) |line_raw| {
        var line = line_raw;
        if (line.len > 0 and line[line.len - 1] == '\r') {
            line = line[0 .. line.len - 1];
        }
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "untrusted comment:")) continue;
        if (std.mem.startsWith(u8, line, "trusted comment:")) continue;
        found = line;
        break;
    }
    return found;
}

fn decodeBase64Alloc(allocator: std.mem.Allocator, b64: []const u8) ![]u8 {
    const out_len = try std.base64.standard.Decoder.calcSizeForSlice(b64);
    const out = try allocator.alloc(u8, out_len);
    errdefer allocator.free(out);
    try std.base64.standard.Decoder.decode(out, b64);
    return out;
}

fn readSmallFile(allocator: std.mem.Allocator, path: []const u8, max_size: usize) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, max_size);
}

fn hashFile(path: []const u8) ![Blake2b512.digest_length]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var hasher = Blake2b512.init(.{});
    var buffer: [64 * 1024]u8 = undefined;
    while (true) {
        const n = try file.read(&buffer);
        if (n == 0) break;
        hasher.update(buffer[0..n]);
    }

    var digest: [Blake2b512.digest_length]u8 = undefined;
    hasher.final(&digest);
    return digest;
}
