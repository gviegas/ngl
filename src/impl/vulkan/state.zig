const std = @import("std");

const ngl = @import("../../ngl.zig");
const Error = ngl.Error;
const Impl = @import("../Impl.zig");
const c = @import("../c.zig");
const conv = @import("conv.zig");
const Device = @import("init.zig").Device;
const PipelineLayout = @import("desc.zig").PipelineLayout;

pub const Pipeline = struct {
    handle: c.VkPipeline,
    modules: [max_module]c.VkShaderModule,

    const max_module = 2;

    pub inline fn cast(impl: *Impl.Pipeline) *Pipeline {
        return @ptrCast(@alignCast(impl));
    }

    pub fn initGraphics(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        desc: ngl.Pipeline.Desc(ngl.GraphicsState),
        pipelines: []ngl.Pipeline,
    ) Error!void {
        const dev = Device.cast(device);

        // TODO
        _ = dev;
        _ = allocator;
        _ = desc;
        _ = pipelines;
        return Error.Other;
    }

    pub fn initCompute(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        desc: ngl.Pipeline.Desc(ngl.ComputeState),
        pipelines: []ngl.Pipeline,
    ) Error!void {
        const dev = Device.cast(device);

        var create_infos = try allocator.alloc(c.VkComputePipelineCreateInfo, desc.states.len);
        defer allocator.free(create_infos);

        for (desc.states, create_infos) |state, *info| {
            info.* = .{
                .sType = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .stage = undefined, // Set below
                .layout = PipelineLayout.cast(state.layout.impl).handle,
                // TODO: Expose these
                .basePipelineHandle = null,
                .basePipelineIndex = -1,
            };
        }

        var module_create_infos: ?[]c.VkShaderModuleCreateInfo = null;
        defer if (module_create_infos) |x| allocator.free(x);

        var modules = try allocator.alloc(c.VkShaderModule, desc.states.len);
        defer allocator.free(modules);
        errdefer for (modules) |m| {
            if (m == null) break;
            dev.vkDestroyShaderModule(m, null);
        };

        if (false) { // TODO: Don't create modules if maintenance5 is available
            @memset(modules, null);
            // TODO...
        } else {
            for (desc.states, modules, create_infos) |state, *module, *info| {
                errdefer module.* = null;

                try conv.check(dev.vkCreateShaderModule(&.{
                    .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .codeSize = state.stage.code.len,
                    .pCode = @as([*]const u32, @ptrCast(state.stage.code.ptr)),
                }, null, module));

                info.stage = .{
                    .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                    .pNext = null,
                    .flags = 0,
                    .stage = c.VK_SHADER_STAGE_COMPUTE_BIT,
                    .module = module.*,
                    .pName = state.stage.name,
                    .pSpecializationInfo = null, // TODO
                };
            }
        }

        var handles = try allocator.alloc(c.VkPipeline, create_infos.len);
        defer allocator.free(handles);

        try conv.check(dev.vkCreateComputePipelines(
            if (desc.cache) |x| PipelineCache.cast(x.impl).handle else null,
            @intCast(create_infos.len),
            create_infos.ptr,
            null,
            handles.ptr,
        ));

        for (pipelines, handles, 0..) |*pl, h, i| {
            var ptr = allocator.create(Pipeline) catch |err| {
                for (0..i) |j| {
                    allocator.destroy(cast(pipelines[j].impl));
                    pipelines[j].impl = undefined;
                }
                return err;
            };
            @memset(ptr.modules[1..], null);
            ptr.handle = h;
            ptr.modules[0] = modules[i];
            pl.*.impl = @ptrCast(ptr);
        }
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        pipeline: *Impl.Pipeline,
        _: ngl.Pipeline.Type,
    ) void {
        const dev = Device.cast(device);
        const pl = cast(pipeline);
        dev.vkDestroyPipeline(pl.handle, null);
        for (pl.modules) |module|
            if (module) |m| dev.vkDestroyShaderModule(m, null) else break;
        allocator.destroy(pl);
    }
};

pub const PipelineCache = struct {
    handle: c.VkPipelineCache,

    pub inline fn cast(impl: *Impl.PipelineCache) *PipelineCache {
        return @ptrCast(@alignCast(impl));
    }

    pub fn init(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        desc: ngl.PipelineCache.Desc,
    ) Error!*Impl.PipelineCache {
        const dev = Device.cast(device);

        var ptr = try allocator.create(PipelineCache);
        errdefer allocator.destroy(ptr);

        var pl_cache: c.VkPipelineCache = undefined;
        try conv.check(dev.vkCreatePipelineCache(&.{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .initialDataSize = if (desc.initial_data) |x| x.len else 0,
            .pInitialData = if (desc.initial_data) |x| x.ptr else null,
        }, null, &pl_cache));

        ptr.* = .{ .handle = pl_cache };
        return @ptrCast(ptr);
    }

    pub fn deinit(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        device: *Impl.Device,
        pipeline_cache: *Impl.PipelineCache,
    ) void {
        const dev = Device.cast(device);
        const pl_cache = cast(pipeline_cache);
        dev.vkDestroyPipelineCache(pl_cache.handle, null);
        allocator.destroy(pl_cache);
    }
};
