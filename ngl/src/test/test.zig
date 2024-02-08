const std = @import("std");
const testing = std.testing;

pub const gpa = testing.allocator;
pub const context = @import("ctx.zig").context;
pub const platform = @import("plat.zig").platform;

// This can be set to `null` to suppress test output
pub const writer: ?std.fs.File.Writer = std.io.getStdErr().writer();

test {
    _ = @import("inst.zig");
    _ = @import("dev.zig");
    _ = @import("fence.zig");
    _ = @import("sema.zig");
    _ = @import("splr.zig");
    _ = @import("image.zig");
    _ = @import("buf.zig");
    _ = @import("layt.zig");
    _ = @import("desc_pool.zig");
    _ = @import("desc_set.zig");
    _ = @import("rp.zig");
    _ = @import("fb.zig");
    _ = @import("pl_cache.zig");
    _ = @import("pl.zig");
    _ = @import("query_pool.zig");
    _ = @import("mem.zig");
    _ = @import("fmt.zig");
    _ = @import("cmd_pool.zig");
    _ = @import("cmd_buf.zig");
    _ = @import("queue.zig");
    _ = @import("fill_buf.zig");
    _ = @import("copy_buf.zig");
    _ = @import("copy_buf_img.zig");
    _ = @import("disp.zig");
    _ = @import("draw.zig");
    _ = @import("depth.zig");
    _ = @import("sten.zig");
    _ = @import("pass_input.zig");
    _ = @import("spec.zig");
    _ = @import("disp_indir.zig");
    _ = @import("occ_query.zig");
    _ = @import("tms_query.zig");
    _ = @import("sf.zig");
    _ = @import("sc.zig");
}
