const std = @import("std");

const ngl = @import("../ngl.zig");
const DriverApi = ngl.DriverApi;
const CommandBuffer = ngl.CommandBuffer;
const PipelineStage = ngl.PipelineStage;
const Fence = ngl.Fence;
const Semaphore = ngl.Semaphore;
const SwapChain = ngl.SwapChain;
const Error = ngl.Error;
const Impl = @import("../impl/Impl.zig");

pub const Instance = struct {
    impl: Impl.Instance,

    pub const Desc = struct {
        presentation: bool = true,
        debugging: bool = false,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, desc: Desc) Error!Self {
        try Impl.init(allocator);
        return .{ .impl = try Impl.get().initInstance(allocator, desc) };
    }

    /// Caller is responsible for freeing the returned slice.
    pub fn listDevices(self: *Self, allocator: std.mem.Allocator) Error![]Device.Desc {
        return Impl.get().listDevices(allocator, self.impl);
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        Impl.get().deinitInstance(allocator, self.impl);
        self.* = undefined;
    }

    /// One can use this to find out which type of shader code
    /// the implementation expects.
    pub fn getDriverApi(self: Self) DriverApi {
        _ = self;
        return Impl.getDriverApi();
    }
};

pub const Device = struct {
    impl: Impl.Device,
    queues: [Queue.max]Queue,
    queue_n: u8,
    mem_types: [Memory.max_type]Memory.Type,
    mem_type_n: u8,

    pub const Type = enum {
        discrete_gpu,
        integrated_gpu,
        cpu,
        other,
    };

    pub const Desc = struct {
        type: Type,
        queues: [Queue.max]?Queue.Desc,
        feature_set: Feature.Set,
        impl: ?struct {
            impl: u64,
            info: [4]u64,
        } = null,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, instance: *Instance, desc: Desc) Error!Self {
        var self = Self{
            .impl = try Impl.get().initDevice(allocator, instance.impl, desc),
            .queues = undefined,
            .queue_n = 0,
            .mem_types = undefined,
            .mem_type_n = 0,
        };
        // Track the current element in `desc.queues` since it
        // might be interspersed with `null`s
        var queue_i: usize = 0;
        var queue_alloc: [Queue.max]Impl.Queue = undefined;
        const queues = Impl.get().getQueues(&queue_alloc, self.impl);
        for (self.queues[0..queues.len], queues) |*queue, impl| {
            // This assumes that implementations won't reorder
            // the queues - the order must match `desc`'s
            while (desc.queues[queue_i] == null) : (queue_i += 1) {}
            queue.* = .{
                .impl = impl,
                .capabilities = desc.queues[queue_i].?.capabilities,
                .priority = desc.queues[queue_i].?.priority,
                .image_transfer_granularity = desc.queues[queue_i].?.image_transfer_granularity,
            };
            queue_i += 1;
        }
        self.queue_n = @intCast(queues.len);
        self.mem_type_n = @intCast(Impl.get().getMemoryTypes(&self.mem_types, self.impl).len);
        return self;
    }

    pub fn alloc(self: *Self, allocator: std.mem.Allocator, desc: Memory.Desc) Error!Memory {
        return .{ .impl = try Impl.get().allocMemory(allocator, self.impl, desc) };
    }

    pub fn free(self: *Self, allocator: std.mem.Allocator, memory: *Memory) void {
        Impl.get().freeMemory(allocator, self.impl, memory.impl);
        memory.* = undefined;
    }

    pub fn wait(self: *Self) Error!void {
        try Impl.get().waitDevice(self.impl);
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        Impl.get().deinitDevice(allocator, self.impl);
        self.* = undefined;
    }

    /// It'll select the first queue whose capabilities are a superset
    /// of what is being requested.
    pub fn findQueue(
        self: Self,
        capabilities: Queue.Capabilities,
        priority: ?Queue.Priority,
    ) ?Queue.Index {
        return self.findQueueOp(.mask, capabilities, priority);
    }

    /// It'll select the first queue whose capabilities are identical
    /// to what is being requested.
    pub fn findQueueExact(
        self: Self,
        capabilities: Queue.Capabilities,
        priority: ?Queue.Priority,
    ) ?Queue.Index {
        return self.findQueueOp(.cmp, capabilities, priority);
    }

    fn findQueueOp(
        self: Self,
        comptime op: enum { mask, cmp },
        capabilities: Queue.Capabilities,
        priority: ?Queue.Priority,
    ) ?Queue.Index {
        const U = @typeInfo(Queue.Capabilities).Struct.backing_integer.?;
        var idx: ?Queue.Index = null;
        for (self.queues[0..self.queue_n], 0..) |q, i| {
            const j: Queue.Index = @intCast(i);

            const mask: U = @bitCast(q.capabilities);
            const bits: U = @bitCast(capabilities);

            switch (op) {
                .mask => if (bits & mask != bits) continue,
                .cmp => if (bits != mask) continue,
            }
            if (priority) |x| {
                if (x == q.priority) {
                    idx = j;
                    break;
                }
            } else {
                idx = j;
                if (q.priority != .low)
                    break;
            }
        }
        return idx;
    }
};

pub const Queue = struct {
    impl: Impl.Queue,
    capabilities: Capabilities,
    priority: Priority,
    image_transfer_granularity: ImageTransferGranularity,

    pub const Index = u2;
    pub const max = 4;

    pub const Capabilities = packed struct {
        graphics: bool = false,
        compute: bool = false,
        // This is guaranteed to be set on queues that support
        // graphics and/or compute.
        transfer: bool = false,
    };

    pub const Priority = enum {
        default,
        low,
        high,
    };

    /// This is only meaningful for transfer-only queues,
    /// as graphics/compute queues will always report `.one`.
    pub const ImageTransferGranularity = enum {
        whole_level,
        one,
    };

    pub const Desc = struct {
        capabilities: Capabilities,
        priority: Priority,
        image_transfer_granularity: ImageTransferGranularity,
        impl: ?struct {
            impl: u64,
            info: [4]u64,
        },
    };

    pub const Submit = struct {
        commands: []const CommandBufferSubmit,
        wait: []const SemaphoreSubmit,
        signal: []const SemaphoreSubmit,

        pub const CommandBufferSubmit = struct {
            command_buffer: *CommandBuffer,
        };

        pub const SemaphoreSubmit = struct {
            semaphore: *Semaphore,
            stage_mask: PipelineStage.Flags,
        };
    };

    pub const Present = struct {
        swap_chain: *SwapChain,
        image_index: SwapChain.Index,
    };

    const Self = @This();

    /// Every submitted command buffer must have been ended,
    /// and must not be pending execution.
    /// Only allowed for command buffers whose level is `.primary`.
    pub fn submit(
        self: *Self,
        allocator: std.mem.Allocator,
        device: *Device,
        fence: ?*Fence,
        submits: []const Submit,
    ) Error!void {
        try Impl.get().submit(
            allocator,
            device.impl,
            self.impl,
            if (fence) |x| x.impl else null,
            submits,
        );
    }

    /// `Feature.presentation`.
    /// One must ensure that the queue is compatible with the surface
    /// of every swap chain in `presents`.
    pub fn present(
        self: *Self,
        allocator: std.mem.Allocator,
        device: *Device,
        wait_semaphores: []const *Semaphore,
        presents: []const Present,
    ) Error!void {
        try Impl.get().present(allocator, device.impl, self.impl, wait_semaphores, presents);
    }

    pub fn wait(self: *Self, device: *Device) Error!void {
        try Impl.get().waitQueue(device.impl, self.impl);
    }
};

pub const Memory = struct {
    impl: Impl.Memory,

    pub const TypeIndex = u5;
    pub const max_type = 32;

    pub const HeapIndex = u4;
    pub const max_heap = 16;

    pub const Properties = packed struct {
        device_local: bool = false,
        host_visible: bool = false,
        host_coherent: bool = false,
        host_cached: bool = false,
        lazily_allocated: bool = false,
    };

    pub const Type = struct {
        properties: Properties,
        heap_index: HeapIndex,
    };

    pub const Requirements = struct {
        size: u64,
        alignment: u64,
        type_bits: u32,

        pub inline fn supportsType(self: Requirements, type_index: TypeIndex) bool {
            return self.type_bits & (@as(u32, 1) << type_index) != 0;
        }

        /// It'll select the first memory type whose properties are a
        /// superset of what is being requested.
        pub fn findType(
            self: Requirements,
            device: Device,
            properties: Properties,
            heap_index: ?HeapIndex,
        ) ?TypeIndex {
            return self.findTypeOp(.mask, device, properties, heap_index);
        }

        /// It'll select the first memory type whose properties are
        /// identical to what is being requested.
        pub fn findTypeExact(
            self: Requirements,
            device: Device,
            properties: Properties,
            heap_index: ?HeapIndex,
        ) ?TypeIndex {
            return self.findTypeOp(.cmp, device, properties, heap_index);
        }

        fn findTypeOp(
            self: Requirements,
            comptime op: enum { mask, cmp },
            device: Device,
            properties: Properties,
            heap_index: ?HeapIndex,
        ) ?TypeIndex {
            const U = @typeInfo(Properties).Struct.backing_integer.?;
            for (0..device.mem_type_n) |i| {
                const idx: TypeIndex = @intCast(i);
                const typ: Type = device.mem_types[idx];

                if (!self.supportsType(idx)) continue;
                if (heap_index) |x|
                    if (x != typ.heap_index) continue;

                const mask: U = @bitCast(typ.properties);
                const bits: U = @bitCast(properties);

                switch (op) {
                    .mask => if (bits & mask == bits) return idx,
                    .cmp => if (bits == mask) return idx,
                }
            }
            return null;
        }
    };

    pub const Desc = struct {
        size: u64,
        type_index: TypeIndex,
    };

    const Self = @This();

    // TODO: Consider storing the size of the memory allocation
    // so this method can return a slice
    pub fn map(self: *Self, device: *Device, offset: u64, size: ?u64) Error![*]u8 {
        return try Impl.get().mapMemory(device.impl, self.impl, offset, size);
    }

    // TODO: Consider tracking memory state
    pub fn unmap(self: *Self, device: *Device) void {
        Impl.get().unmapMemory(device.impl, self.impl);
    }

    pub fn flushMapped(
        self: *Self,
        allocator: std.mem.Allocator,
        device: *Device,
        offsets: []const u64,
        sizes: ?[]const u64,
    ) Error!void {
        try Impl.get().flushMappedMemory(allocator, device.impl, self.impl, offsets, sizes);
    }

    pub fn invalidateMapped(
        self: *Self,
        allocator: std.mem.Allocator,
        device: *Device,
        offsets: []const u64,
        sizes: ?[]const u64,
    ) Error!void {
        try Impl.get().invalidateMappedMemory(allocator, device.impl, self.impl, offsets, sizes);
    }
};

// TODO: Other optional features
pub const Feature = union(enum) {
    /// The `core` feature is always supported.
    core: struct {
        memory: struct {
            max_count: u64 = 4096,
            max_size: u64 = 1073741824,
            min_map_alignment: u64,
        },
        sampler: struct {
            max_count: u32 = 4000,
            max_anisotropy: u5 = 1,
            address_mode_mirror_clamp_to_edge: bool,
        },
        image: struct {
            max_dimension_1d: u32 = 4096,
            max_dimension_2d: u32 = 4096,
            max_dimension_cube: u32 = 4096,
            max_dimension_3d: u32 = 256,
            max_layers: u32 = 256,
            sampled_color_sample_counts: ngl.SampleCount.Flags = .{ .@"1" = true, .@"4" = true },
            sampled_integer_sample_counts: ngl.SampleCount.Flags = .{ .@"1" = true },
            sampled_depth_sample_counts: ngl.SampleCount.Flags = .{ .@"1" = true, .@"4" = true },
            sampled_stencil_sample_counts: ngl.SampleCount.Flags = .{ .@"1" = true, .@"4" = true },
            storage_sample_counts: ngl.SampleCount.Flags = .{ .@"1" = true },
            cube_array: bool,
        },
        buffer: struct {
            max_size: u64 = 1073741824,
            max_texel_elements: u32 = 65536,
            min_texel_offset_alignment: u64 = 256,
        },
        descriptor: struct {
            max_bound_sets: u32 = 4,
            max_samplers: u32 = 96,
            max_sampled_images: u32 = 96,
            max_storage_images: u32 = 24,
            max_uniform_buffers: u32 = 72,
            max_storage_buffers: u32 = 24,
            max_input_attachments: u32 = 4,
            max_per_stage_samplers: u32 = 16,
            max_per_stage_sampled_images: u32 = 16,
            max_per_stage_storage_images: u32 = 4,
            max_per_stage_uniform_buffers: u32 = 12,
            max_per_stage_storage_buffers: u32 = 4,
            max_per_stage_input_attachments: u32 = 4,
            max_per_stage_resources: u32 = 128,
            max_push_constants_size: u32 = 128,
            min_uniform_buffer_offset_alignment: u64 = 256,
            max_uniform_buffer_range: u64 = 16384,
            min_storage_buffer_offset_alignment: u64 = 256,
            max_storage_buffer_range: u64 = 134217728,
        },
        subpass: struct {
            max_color_attachments: u17 = 4,
        },
        frame_buffer: struct {
            max_width: u32 = 4096,
            max_height: u32 = 4096,
            max_layers: u32 = 256,
            color_sample_counts: ngl.SampleCount.Flags = .{ .@"1" = true, .@"4" = true },
            integer_sample_counts: ngl.SampleCount.Flags = .{ .@"1" = true },
            depth_sample_counts: ngl.SampleCount.Flags = .{ .@"1" = true, .@"4" = true },
            stencil_sample_counts: ngl.SampleCount.Flags = .{ .@"1" = true, .@"4" = true },
            no_attachment_sample_counts: ngl.SampleCount.Flags = .{ .@"1" = true, .@"4" = true },
        },
        draw: struct {
            max_index_value: u32 = 16777215,
            indirect_command: bool,
            indexed_indirect_command: bool,
            max_indirect_count: u32 = 1,
            indirect_first_instance: bool,
        },
        dispatch: struct {
            indirect_command: bool,
        },
        primitive: struct {
            max_bindings: u32 = 8,
            max_attributes: u32 = 16,
            max_binding_stride: u32 = 2048,
            max_attribute_offset: u32 = 2047,
        },
        viewport: struct {
            max_width: u32 = 4096,
            max_height: u32 = 4096,
            min_bound: f32 = -8192,
            max_bound: f32 = 8191,
        },
        rasterization: struct {
            polygon_mode_line: bool,
            depth_clamp: bool,
            depth_bias_clamp: bool,
            alpha_to_one: bool,
        },
        color_blend: struct {
            independent_blend: bool,
        },
        vertex: struct {
            max_output_components: u32 = 64,
            stores_and_atomics: bool,
        },
        fragment: struct {
            max_input_components: u32 = 64,
            max_output_attachments: u32 = 4,
            max_combined_output_resources: u32 = 4,
            stores_and_atomics: bool,
        },
        compute: struct {
            max_shared_memory_size: u32 = 16384,
            max_group_count_x: u32 = 65535,
            max_group_count_y: u32 = 65535,
            max_group_count_z: u32 = 65535,
            max_local_invocations: u32 = 128,
            max_local_size_x: u32 = 128,
            max_local_size_y: u32 = 128,
            max_local_size_z: u32 = 64,
        },
        query: struct {
            occlusion_precise: bool,
            timestamp: [Queue.max]bool,
            inherited: bool,
        },
    },

    /// Allow the creation of swap chains.
    /// This feature is only meaningful when the instance used to
    /// create the device also supports presentation.
    presentation,

    pub const Set = @Type(.{ .Struct = .{
        .layout = .Packed,
        .fields = blk: {
            const type_info = @typeInfo(Feature);
            if (!std.mem.eql(u8, type_info.Union.fields[0].name, "core"))
                @compileError("Feature.core must come first");
            const StructField = std.builtin.Type.StructField;
            var fields: []const StructField = &[_]StructField{.{
                .name = type_info.Union.fields[0].name,
                .type = bool,
                .default_value = @ptrCast(&true),
                .is_comptime = false,
                .alignment = 0,
            }};
            for (type_info.Union.fields[1..]) |f|
                fields = fields ++ &[_]StructField{.{
                    .name = f.name,
                    .type = bool,
                    .default_value = @ptrCast(&false),
                    .is_comptime = false,
                    .alignment = 0,
                }};
            break :blk fields;
        },
        .decls = &.{},
        .is_tuple = false,
    } });

    /// It returns `null` if the requested feature isn't supported
    /// by the device (note that `core` is always supported).
    /// `device_desc` must have been obtained through a call to
    /// `instance.listDevices`.
    pub fn get(
        allocator: std.mem.Allocator,
        instance: *Instance,
        device_desc: Device.Desc,
        comptime tag: @typeInfo(Feature).Union.tag_type.?,
    ) ?@typeInfo(Feature).Union.fields[@intFromEnum(tag)].type {
        var feat = @unionInit(Feature, @tagName(tag), undefined);
        return if (Impl.get().getFeature(allocator, instance.impl, device_desc, &feat)) |_|
            @field(feat, @tagName(tag))
        else |_|
            null;
    }
};
