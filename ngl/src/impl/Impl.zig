const std = @import("std");
const builtin = @import("builtin");

const log = std.log.scoped(.@"ngl/impl");

const ngl = @import("../ngl.zig");
const Error = ngl.Error;

ptr: *anyopaque,
vtable: *const VTable,

/// It should be instantiated with a different `T` every time
/// to guarantee type safety.
fn Type(comptime T: type) type {
    return struct {
        val: u64,

        pub fn ptr(self: @This(), comptime Pointee: type) *Pointee {
            const p: *anyopaque = @ptrFromInt(self.val);
            return @ptrCast(@alignCast(p));
        }

        pub const ApiType = T;
    };
}

pub const Gpu = Type(ngl.Gpu);
pub const Device = Type(ngl.Device);
pub const Queue = Type(ngl.Queue);
pub const Memory = Type(ngl.Memory);
pub const CommandPool = Type(ngl.CommandPool);
pub const CommandBuffer = Type(ngl.CommandBuffer);
pub const Fence = Type(ngl.Fence);
pub const Semaphore = Type(ngl.Semaphore);
pub const Buffer = Type(ngl.Buffer);
pub const BufferView = Type(ngl.BufferView);
pub const Image = Type(ngl.Image);
pub const ImageView = Type(ngl.ImageView);
pub const Sampler = Type(ngl.Sampler);
pub const Shader = Type(ngl.Shader);
pub const ShaderLayout = Type(ngl.ShaderLayout);
pub const DescriptorSetLayout = Type(ngl.DescriptorSetLayout);
pub const DescriptorPool = Type(ngl.DescriptorPool);
pub const DescriptorSet = Type(ngl.DescriptorSet);
pub const QueryPool = Type(ngl.QueryPool);
pub const Surface = Type(ngl.Surface);
pub const Swapchain = Type(ngl.Swapchain);

pub const VTable = struct {
    deinit: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,

    getGpus: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) Error![]ngl.Gpu,

    // Device ----------------------------------------------

    initDevice: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        gpu: ngl.Gpu,
    ) Error!Device,

    getQueues: *const fn (
        ctx: *anyopaque,
        allocation: *[ngl.Queue.max]Queue,
        device: Device,
    ) []Queue,

    getMemoryTypes: *const fn (
        ctx: *anyopaque,
        allocation: *[ngl.Memory.max_type]ngl.Memory.Type,
        device: Device,
    ) []ngl.Memory.Type,

    getMemoryHeaps: *const fn (
        ctx: *anyopaque,
        allocation: *[ngl.Memory.max_heap]ngl.Memory.Heap,
        device: Device,
    ) []ngl.Memory.Heap,

    allocMemory: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.Memory.Desc,
    ) Error!Memory,

    freeMemory: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        memory: Memory,
    ) void,

    waitDevice: *const fn (ctx: *anyopaque, device: Device) Error!void,

    deinitDevice: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, device: Device) void,

    // Queue -----------------------------------------------

    submit: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        queue: Queue,
        fence: ?Fence,
        submits: []const ngl.Queue.Submit,
    ) Error!void,

    present: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        queue: Queue,
        wait_semaphores: []const *ngl.Semaphore,
        presents: []const ngl.Queue.Present,
    ) Error!void,

    waitQueue: *const fn (ctx: *anyopaque, device: Device, queue: Queue) Error!void,

    // Memory ----------------------------------------------

    mapMemory: *const fn (
        ctx: *anyopaque,
        device: Device,
        memory: Memory,
        offset: u64,
        size: u64,
    ) Error![]u8,

    unmapMemory: *const fn (ctx: *anyopaque, device: Device, memory: Memory) void,

    flushMappedMemory: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        memory: Memory,
        offsets: []const u64,
        sizes: []const u64,
    ) Error!void,

    invalidateMappedMemory: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        memory: Memory,
        offsets: []const u64,
        sizes: []const u64,
    ) Error!void,

    // Feature ---------------------------------------------

    getFeature: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        gpu: ngl.Gpu,
        feature: *ngl.Feature,
    ) Error!void,

    // CommandPool -----------------------------------------

    initCommandPool: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.CommandPool.Desc,
    ) Error!CommandPool,

    allocCommandBuffers: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_pool: CommandPool,
        desc: ngl.CommandBuffer.Desc,
        command_buffers: []ngl.CommandBuffer,
    ) Error!void,

    resetCommandPool: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_pool: CommandPool,
        mode: ngl.CommandPool.ResetMode,
    ) Error!void,

    freeCommandBuffers: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_pool: CommandPool,
        command_buffers: []const *ngl.CommandBuffer,
    ) void,

    deinitCommandPool: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_pool: CommandPool,
    ) void,

    // CommandBuffer ---------------------------------------

    beginCommandBuffer: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        desc: ngl.Cmd.Desc,
    ) Error!void,

    setShaders: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        types: []const ngl.Shader.Type,
        shaders: []const ?*ngl.Shader,
    ) void,

    setDescriptors: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        bind_point: ngl.Cmd.BindPoint,
        shader_layout: ShaderLayout,
        first_set: u32,
        descriptor_sets: []const *ngl.DescriptorSet,
    ) void,

    setPushConstants: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        shader_layout: ShaderLayout,
        shader_mask: ngl.Shader.Type.Flags,
        offset: u16,
        constants: []align(4) const u8,
    ) void,

    setVertexInput: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        bindings: []const ngl.Cmd.VertexInputBinding,
        attributes: []const ngl.Cmd.VertexInputAttribute,
    ) void,

    setPrimitiveTopology: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        topology: ngl.Cmd.PrimitiveTopology,
    ) void,

    setIndexBuffer: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        index_type: ngl.Cmd.IndexType,
        buffer: Buffer,
        offset: u64,
        size: u64,
    ) void,

    setVertexBuffers: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        first_binding: u32,
        buffers: []const *ngl.Buffer,
        offsets: []const u64,
        sizes: []const u64,
    ) void,

    setViewports: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        viewports: []const ngl.Cmd.Viewport,
    ) void,

    setScissorRects: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        scissor_rects: []const ngl.Cmd.ScissorRect,
    ) void,

    setRasterizationEnable: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        enable: bool,
    ) void,

    setPolygonMode: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        polygon_mode: ngl.Cmd.PolygonMode,
    ) void,

    setCullMode: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        cull_mode: ngl.Cmd.CullMode,
    ) void,

    setFrontFace: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        front_face: ngl.Cmd.FrontFace,
    ) void,

    setSampleCount: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        sample_count: ngl.SampleCount,
    ) void,

    setSampleMask: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        sample_mask: u64,
    ) void,

    setDepthBiasEnable: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        enable: bool,
    ) void,

    setDepthBias: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        value: f32,
        slope: f32,
        clamp: f32,
    ) void,

    setDepthTestEnable: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        enable: bool,
    ) void,

    setDepthCompareOp: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        compare_op: ngl.CompareOp,
    ) void,

    setDepthWriteEnable: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        enable: bool,
    ) void,

    setStencilTestEnable: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        enable: bool,
    ) void,

    setStencilOp: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        stencil_face: ngl.Cmd.StencilFace,
        fail_op: ngl.Cmd.StencilOp,
        pass_op: ngl.Cmd.StencilOp,
        depth_fail_op: ngl.Cmd.StencilOp,
        compare_op: ngl.CompareOp,
    ) void,

    setStencilReadMask: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        stencil_face: ngl.Cmd.StencilFace,
        mask: u32,
    ) void,

    setStencilWriteMask: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        stencil_face: ngl.Cmd.StencilFace,
        mask: u32,
    ) void,

    setStencilReference: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        stencil_face: ngl.Cmd.StencilFace,
        reference: u32,
    ) void,

    setColorBlendEnable: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        first_attachment: ngl.Cmd.ColorAttachmentIndex,
        enable: []const bool,
    ) void,

    setColorBlend: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        first_attachment: ngl.Cmd.ColorAttachmentIndex,
        blend: []const ngl.Cmd.Blend,
    ) void,

    setColorWrite: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        first_attachment: ngl.Cmd.ColorAttachmentIndex,
        write_masks: []const ngl.Cmd.ColorMask,
    ) void,

    setBlendConstants: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        constants: [4]f32,
    ) void,

    beginRendering: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        rendering: ngl.Cmd.Rendering,
    ) void,

    endRendering: *const fn (ctx: *anyopaque, device: Device, command_buffer: CommandBuffer) void,

    draw: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        vertex_count: u32,
        instance_count: u32,
        first_vertex: u32,
        first_instance: u32,
    ) void,

    drawIndexed: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        index_count: u32,
        instance_count: u32,
        first_index: u32,
        vertex_offset: i32,
        first_instance: u32,
    ) void,

    drawIndirect: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        buffer: Buffer,
        offset: u64,
        draw_count: u32,
        stride: u32,
    ) void,

    drawIndexedIndirect: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        buffer: Buffer,
        offset: u64,
        draw_count: u32,
        stride: u32,
    ) void,

    dispatch: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        group_count_x: u32,
        group_count_y: u32,
        group_count_z: u32,
    ) void,

    dispatchIndirect: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        buffer: Buffer,
        offset: u64,
    ) void,

    clearBuffer: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        buffer: Buffer,
        offset: u64,
        size: ?u64,
        value: u8,
    ) void,

    copyBuffer: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        copies: []const ngl.Cmd.BufferCopy,
    ) void,

    copyImage: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        copies: []const ngl.Cmd.ImageCopy,
    ) void,

    copyBufferToImage: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        copies: []const ngl.Cmd.BufferImageCopy,
    ) void,

    copyImageToBuffer: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        copies: []const ngl.Cmd.BufferImageCopy,
    ) void,

    resetQueryPool: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        query_pool: QueryPool,
        first_query: u32,
        query_count: u32,
    ) void,

    beginQuery: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        query_type: ngl.QueryType,
        query_pool: QueryPool,
        query: u32,
        control: ngl.Cmd.QueryControl,
    ) void,

    endQuery: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        query_type: ngl.QueryType,
        query_pool: QueryPool,
        query: u32,
    ) void,

    writeTimestamp: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        stage: ngl.Stage,
        query_pool: QueryPool,
        query: u32,
    ) void,

    copyQueryPoolResults: *const fn (
        ctx: *anyopaque,
        device: Device,
        command_buffer: CommandBuffer,
        query_type: ngl.QueryType,
        query_pool: QueryPool,
        first_query: u32,
        query_count: u32,
        dest: Buffer,
        dest_offset: u64,
        result: ngl.Cmd.QueryResult,
    ) void,

    barrier: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        barriers: []const ngl.Cmd.Barrier,
    ) void,

    executeCommands: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
        secondary_command_buffers: []const *ngl.CommandBuffer,
    ) void,

    endCommandBuffer: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        command_buffer: CommandBuffer,
    ) Error!void,

    // Fence -----------------------------------------------

    initFence: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.Fence.Desc,
    ) Error!Fence,

    resetFences: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        fences: []const *ngl.Fence,
    ) Error!void,

    waitFences: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        timeout: u64,
        fences: []const *ngl.Fence,
    ) Error!void,

    getFenceStatus: *const fn (
        ctx: *anyopaque,
        device: Device,
        fence: Fence,
    ) Error!ngl.Fence.Status,

    deinitFence: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        fence: Fence,
    ) void,

    // Semaphore -------------------------------------------

    initSemaphore: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.Semaphore.Desc,
    ) Error!Semaphore,

    deinitSemaphore: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        semaphore: Semaphore,
    ) void,

    // Format ----------------------------------------------

    getFormatFeatures: *const fn (
        ctx: *anyopaque,
        device: Device,
        format: ngl.Format,
    ) ngl.Format.FeatureSet,

    // Buffer ----------------------------------------------

    initBuffer: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.Buffer.Desc,
    ) Error!Buffer,

    getMemoryRequirementsBuffer: *const fn (
        ctx: *anyopaque,
        device: Device,
        buffer: Buffer,
    ) ngl.Memory.Requirements,

    bindBuffer: *const fn (
        ctx: *anyopaque,
        device: Device,
        buffer: Buffer,
        memory: Memory,
        memory_offset: u64,
    ) Error!void,

    deinitBuffer: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        buffer: Buffer,
    ) void,

    // BufferView ------------------------------------------

    initBufferView: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.BufferView.Desc,
    ) Error!BufferView,

    deinitBufferView: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        buffer: BufferView,
    ) void,

    // Image -----------------------------------------------

    initImage: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.Image.Desc,
    ) Error!Image,

    getImageCapabilities: *const fn (
        ctx: *anyopaque,
        device: Device,
        type: ngl.Image.Type,
        format: ngl.Format,
        tiling: ngl.Image.Tiling,
        usage: ngl.Image.Usage,
        misc: ngl.Image.Misc,
    ) Error!ngl.Image.Capabilities,

    getImageDataLayout: *const fn (
        ctx: *anyopaque,
        device: Device,
        image: Image,
        type: ngl.Image.Type,
        aspect: ngl.Image.Aspect,
        level: u32,
        layer: u32,
    ) ngl.Image.DataLayout,

    getMemoryRequirementsImage: *const fn (
        ctx: *anyopaque,
        device: Device,
        image: Image,
    ) ngl.Memory.Requirements,

    bindImage: *const fn (
        ctx: *anyopaque,
        device: Device,
        image: Image,
        memory: Memory,
        memory_offset: u64,
    ) Error!void,

    deinitImage: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        image: Image,
    ) void,

    // ImageView -------------------------------------------

    initImageView: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.ImageView.Desc,
    ) Error!ImageView,

    deinitImageView: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        image_view: ImageView,
    ) void,

    // Sampler ---------------------------------------------

    initSampler: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.Sampler.Desc,
    ) Error!Sampler,

    deinitSampler: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        sampler: Sampler,
    ) void,

    // Shader ----------------------------------------------

    initShader: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        descs: []const ngl.Shader.Desc,
        shaders: []Error!ngl.Shader,
    ) Error!void,

    deinitShader: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        shader: Shader,
    ) void,

    // ShaderLayout ----------------------------------------

    initShaderLayout: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.ShaderLayout.Desc,
    ) Error!ShaderLayout,

    deinitShaderLayout: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        shader_layout: ShaderLayout,
    ) void,

    // DescriptorSetLayout ---------------------------------

    initDescriptorSetLayout: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.DescriptorSetLayout.Desc,
    ) Error!DescriptorSetLayout,

    deinitDescriptorSetLayout: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        descriptor_set_layout: DescriptorSetLayout,
    ) void,

    // DescriptorPool --------------------------------------

    initDescriptorPool: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.DescriptorPool.Desc,
    ) Error!DescriptorPool,

    allocDescriptorSets: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        descriptor_pool: DescriptorPool,
        desc: ngl.DescriptorSet.Desc,
        descriptor_sets: []ngl.DescriptorSet,
    ) Error!void,

    resetDescriptorPool: *const fn (
        ctx: *anyopaque,
        device: Device,
        descriptor_pool: DescriptorPool,
    ) Error!void,

    deinitDescriptorPool: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        descriptor_pool: DescriptorPool,
    ) void,

    // DescriptorSet ---------------------------------------

    writeDescriptorSets: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        writes: []const ngl.DescriptorSet.Write,
    ) Error!void,

    // QueryType -------------------------------------------

    getQueryLayout: *const fn (
        ctx: *anyopaque,
        device: Device,
        query_type: ngl.QueryType,
        query_count: u32,
        with_availability: bool,
    ) ngl.QueryType.Layout,

    // QueryPool -------------------------------------------

    initQueryPool: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.QueryPool.Desc,
    ) Error!QueryPool,

    deinitQueryPool: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        query_pool: QueryPool,
    ) void,

    // QueryResolve ----------------------------------------

    resolveQueryOcclusion: *const fn (
        ctx: *anyopaque,
        device: Device,
        first_result: u32,
        with_availability: bool,
        source: []const u8,
        dest: @TypeOf((ngl.QueryResolve(.occlusion){}).resolved_results),
    ) Error!void,

    resolveQueryTimestamp: *const fn (
        ctx: *anyopaque,
        device: Device,
        first_result: u32,
        with_availability: bool,
        source: []const u8,
        dest: @TypeOf((ngl.QueryResolve(.timestamp){}).resolved_results),
    ) Error!void,

    // Surface ---------------------------------------------

    initSurface: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        desc: ngl.Surface.Desc,
    ) Error!Surface,

    isSurfaceCompatible: *const fn (
        ctx: *anyopaque,
        surface: Surface,
        gpu: ngl.Gpu,
        queue: ngl.Queue.Index,
    ) Error!bool,

    getSurfacePresentModes: *const fn (
        ctx: *anyopaque,
        surface: Surface,
        gpu: ngl.Gpu,
    ) Error!ngl.Surface.PresentMode.Flags,

    getSurfaceFormats: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        surface: Surface,
        gpu: ngl.Gpu,
    ) Error![]ngl.Surface.Format,

    getSurfaceCapabilities: *const fn (
        ctx: *anyopaque,
        surface: Surface,
        gpu: ngl.Gpu,
        present_mode: ngl.Surface.PresentMode,
    ) Error!ngl.Surface.Capabilities,

    deinitSurface: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        surface: Surface,
    ) void,

    // Swapchain -------------------------------------------

    initSwapchain: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        desc: ngl.Swapchain.Desc,
    ) Error!Swapchain,

    getSwapchainImages: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        swapchain: Swapchain,
    ) Error![]ngl.Image,

    nextSwapchainImage: *const fn (
        ctx: *anyopaque,
        device: Device,
        swapchain: Swapchain,
        timeout: u64,
        semaphore: ?Semaphore,
        fence: ?Fence,
    ) Error!ngl.Swapchain.Index,

    deinitSwapchain: *const fn (
        ctx: *anyopaque,
        allocator: std.mem.Allocator,
        device: Device,
        swapchain: Swapchain,
    ) void,
};

const Self = @This();

var lock = std.Thread.Mutex{};
var impl: ?Self = null;
var dapi: ?DriverApi = null;

/// Name of GPU backends that an implementation may use.
pub const DriverApi = enum {
    vulkan,
};

/// It's only valid to call this after `init()` succeeds.
/// `deinit()` invalidates the `Impl`. Don't store it.
pub fn get() *Self {
    std.debug.assert(impl != null);
    return &impl.?;
}

/// Same restrictions as `get`.
pub fn getDriverApi() DriverApi {
    std.debug.assert(dapi != null);
    return dapi.?;
}

// TODO: Debug-check inputs/outputs of these functions.

// TODO: Parameters.
pub fn init(allocator: std.mem.Allocator) Error!void {
    lock.lock();
    defer lock.unlock();
    if (impl) |_| return;
    switch (builtin.os.tag) {
        .linux, .windows => {
            impl = try @import("vulkan/init.zig").init(allocator);
            dapi = .vulkan;
        },
        else => return Error.NotSupported,
    }
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    lock.lock();
    defer lock.unlock();
    if (impl == null) {
        log.warn("Multiple calls to Impl.deinit", .{});
        return;
    }
    self.vtable.deinit(self.ptr, allocator);
    self.* = undefined;
    impl = null;
    dapi = null;
}

pub fn getGpus(self: *Self, allocator: std.mem.Allocator) Error![]ngl.Gpu {
    return self.vtable.getGpus(self.ptr, allocator);
}

pub fn initDevice(self: *Self, allocator: std.mem.Allocator, gpu: ngl.Gpu) Error!Device {
    return self.vtable.initDevice(self.ptr, allocator, gpu);
}

pub fn getQueues(self: *Self, allocation: *[ngl.Queue.max]Queue, device: Device) []Queue {
    return self.vtable.getQueues(self.ptr, allocation, device);
}

pub fn getMemoryTypes(
    self: *Self,
    allocation: *[ngl.Memory.max_type]ngl.Memory.Type,
    device: Device,
) []ngl.Memory.Type {
    return self.vtable.getMemoryTypes(self.ptr, allocation, device);
}

pub fn getMemoryHeaps(
    self: *Self,
    allocation: *[ngl.Memory.max_heap]ngl.Memory.Heap,
    device: Device,
) []ngl.Memory.Heap {
    return self.vtable.getMemoryHeaps(self.ptr, allocation, device);
}

pub fn allocMemory(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.Memory.Desc,
) Error!Memory {
    return self.vtable.allocMemory(self.ptr, allocator, device, desc);
}

pub fn freeMemory(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    memory: Memory,
) void {
    self.vtable.freeMemory(self.ptr, allocator, device, memory);
}

pub fn waitDevice(self: *Self, device: Device) Error!void {
    try self.vtable.waitDevice(self.ptr, device);
}

pub fn deinitDevice(self: *Self, allocator: std.mem.Allocator, device: Device) void {
    self.vtable.deinitDevice(self.ptr, allocator, device);
}

pub fn submit(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    queue: Queue,
    fence: ?Fence,
    submits: []const ngl.Queue.Submit,
) Error!void {
    try self.vtable.submit(self.ptr, allocator, device, queue, fence, submits);
}

pub fn present(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    queue: Queue,
    wait_semaphores: []const *ngl.Semaphore,
    presents: []const ngl.Queue.Present,
) Error!void {
    try self.vtable.present(self.ptr, allocator, device, queue, wait_semaphores, presents);
}

pub fn waitQueue(self: *Self, device: Device, queue: Queue) Error!void {
    try self.vtable.waitQueue(self.ptr, device, queue);
}

pub fn mapMemory(self: *Self, device: Device, memory: Memory, offset: u64, size: u64) Error![]u8 {
    return self.vtable.mapMemory(self.ptr, device, memory, offset, size);
}

pub fn unmapMemory(self: *Self, device: Device, memory: Memory) void {
    self.vtable.unmapMemory(self.ptr, device, memory);
}

pub fn flushMappedMemory(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    memory: Memory,
    offsets: []const u64,
    sizes: []const u64,
) Error!void {
    try self.vtable.flushMappedMemory(self.ptr, allocator, device, memory, offsets, sizes);
}

pub fn invalidateMappedMemory(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    memory: Memory,
    offsets: []const u64,
    sizes: []const u64,
) Error!void {
    try self.vtable.invalidateMappedMemory(self.ptr, allocator, device, memory, offsets, sizes);
}

pub fn getFeature(
    self: *Self,
    allocator: std.mem.Allocator,
    gpu: ngl.Gpu,
    feature: *ngl.Feature,
) Error!void {
    try self.vtable.getFeature(self.ptr, allocator, gpu, feature);
}

pub fn initCommandPool(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.CommandPool.Desc,
) Error!CommandPool {
    return self.vtable.initCommandPool(self.ptr, allocator, device, desc);
}

pub fn allocCommandBuffers(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_pool: CommandPool,
    desc: ngl.CommandBuffer.Desc,
    command_buffers: []ngl.CommandBuffer,
) Error!void {
    try self.vtable.allocCommandBuffers(
        self.ptr,
        allocator,
        device,
        command_pool,
        desc,
        command_buffers,
    );
}

pub fn resetCommandPool(
    self: *Self,
    device: Device,
    command_pool: CommandPool,
    mode: ngl.CommandPool.ResetMode,
) Error!void {
    try self.vtable.resetCommandPool(self.ptr, device, command_pool, mode);
}

pub fn freeCommandBuffers(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_pool: CommandPool,
    command_buffers: []const *ngl.CommandBuffer,
) void {
    self.vtable.freeCommandBuffers(self.ptr, allocator, device, command_pool, command_buffers);
}

pub fn deinitCommandPool(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_pool: CommandPool,
) void {
    self.vtable.deinitCommandPool(self.ptr, allocator, device, command_pool);
}

pub fn beginCommandBuffer(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    desc: ngl.Cmd.Desc,
) Error!void {
    try self.vtable.beginCommandBuffer(self.ptr, allocator, device, command_buffer, desc);
}

pub fn setShaders(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    types: []const ngl.Shader.Type,
    shaders: []const ?*ngl.Shader,
) void {
    self.vtable.setShaders(self.ptr, allocator, device, command_buffer, types, shaders);
}

pub fn setDescriptors(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    bind_point: ngl.Cmd.BindPoint,
    shader_layout: ShaderLayout,
    first_set: u32,
    descriptor_sets: []const *ngl.DescriptorSet,
) void {
    self.vtable.setDescriptors(
        self.ptr,
        allocator,
        device,
        command_buffer,
        bind_point,
        shader_layout,
        first_set,
        descriptor_sets,
    );
}

pub fn setPushConstants(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    shader_layout: ShaderLayout,
    shader_mask: ngl.Shader.Type.Flags,
    offset: u16,
    constants: []align(4) const u8,
) void {
    self.vtable.setPushConstants(
        self.ptr,
        device,
        command_buffer,
        shader_layout,
        shader_mask,
        offset,
        constants,
    );
}

pub fn setVertexInput(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    bindings: []const ngl.Cmd.VertexInputBinding,
    attributes: []const ngl.Cmd.VertexInputAttribute,
) void {
    self.vtable.setVertexInput(
        self.ptr,
        allocator,
        device,
        command_buffer,
        bindings,
        attributes,
    );
}

pub fn setPrimitiveTopology(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    topology: ngl.Cmd.PrimitiveTopology,
) void {
    self.vtable.setPrimitiveTopology(self.ptr, device, command_buffer, topology);
}

pub fn setIndexBuffer(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    index_type: ngl.Cmd.IndexType,
    buffer: Buffer,
    offset: u64,
    size: u64,
) void {
    self.vtable.setIndexBuffer(self.ptr, device, command_buffer, index_type, buffer, offset, size);
}

pub fn setVertexBuffers(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    first_binding: u32,
    buffers: []const *ngl.Buffer,
    offsets: []const u64,
    sizes: []const u64,
) void {
    self.vtable.setVertexBuffers(
        self.ptr,
        allocator,
        device,
        command_buffer,
        first_binding,
        buffers,
        offsets,
        sizes,
    );
}

pub fn setViewports(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    viewports: []const ngl.Cmd.Viewport,
) void {
    self.vtable.setViewports(self.ptr, allocator, device, command_buffer, viewports);
}

pub fn setScissorRects(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    scissor_rects: []const ngl.Cmd.ScissorRect,
) void {
    self.vtable.setScissorRects(self.ptr, allocator, device, command_buffer, scissor_rects);
}

pub fn setRasterizationEnable(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    enable: bool,
) void {
    self.vtable.setRasterizationEnable(self.ptr, device, command_buffer, enable);
}

pub fn setPolygonMode(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    polygon_mode: ngl.Cmd.PolygonMode,
) void {
    self.vtable.setPolygonMode(self.ptr, device, command_buffer, polygon_mode);
}

pub fn setCullMode(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    cull_mode: ngl.Cmd.CullMode,
) void {
    self.vtable.setCullMode(self.ptr, device, command_buffer, cull_mode);
}

pub fn setFrontFace(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    front_face: ngl.Cmd.FrontFace,
) void {
    self.vtable.setFrontFace(self.ptr, device, command_buffer, front_face);
}

pub fn setSampleCount(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    sample_count: ngl.SampleCount,
) void {
    self.vtable.setSampleCount(self.ptr, device, command_buffer, sample_count);
}

pub fn setSampleMask(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    sample_mask: u64,
) void {
    self.vtable.setSampleMask(self.ptr, device, command_buffer, sample_mask);
}

pub fn setDepthBiasEnable(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    enable: bool,
) void {
    self.vtable.setDepthBiasEnable(self.ptr, device, command_buffer, enable);
}

pub fn setDepthBias(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    value: f32,
    slope: f32,
    clamp: f32,
) void {
    self.vtable.setDepthBias(self.ptr, device, command_buffer, value, slope, clamp);
}

pub fn setDepthTestEnable(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    enable: bool,
) void {
    self.vtable.setDepthTestEnable(self.ptr, device, command_buffer, enable);
}

pub fn setDepthCompareOp(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    compare_op: ngl.CompareOp,
) void {
    self.vtable.setDepthCompareOp(self.ptr, device, command_buffer, compare_op);
}

pub fn setDepthWriteEnable(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    enable: bool,
) void {
    self.vtable.setDepthWriteEnable(self.ptr, device, command_buffer, enable);
}

pub fn setStencilTestEnable(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    enable: bool,
) void {
    self.vtable.setStencilTestEnable(self.ptr, device, command_buffer, enable);
}

pub fn setStencilOp(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    stencil_face: ngl.Cmd.StencilFace,
    fail_op: ngl.Cmd.StencilOp,
    pass_op: ngl.Cmd.StencilOp,
    depth_fail_op: ngl.Cmd.StencilOp,
    compare_op: ngl.CompareOp,
) void {
    self.vtable.setStencilOp(
        self.ptr,
        device,
        command_buffer,
        stencil_face,
        fail_op,
        pass_op,
        depth_fail_op,
        compare_op,
    );
}

pub fn setStencilReadMask(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    stencil_face: ngl.Cmd.StencilFace,
    mask: u32,
) void {
    self.vtable.setStencilReadMask(self.ptr, device, command_buffer, stencil_face, mask);
}

pub fn setStencilWriteMask(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    stencil_face: ngl.Cmd.StencilFace,
    mask: u32,
) void {
    self.vtable.setStencilWriteMask(self.ptr, device, command_buffer, stencil_face, mask);
}

pub fn setStencilReference(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    stencil_face: ngl.Cmd.StencilFace,
    reference: u32,
) void {
    self.vtable.setStencilReference(self.ptr, device, command_buffer, stencil_face, reference);
}

pub fn setColorBlendEnable(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    first_attachment: ngl.Cmd.ColorAttachmentIndex,
    enable: []const bool,
) void {
    self.vtable.setColorBlendEnable(
        self.ptr,
        allocator,
        device,
        command_buffer,
        first_attachment,
        enable,
    );
}

pub fn setColorBlend(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    first_attachment: ngl.Cmd.ColorAttachmentIndex,
    blend: []const ngl.Cmd.Blend,
) void {
    self.vtable.setColorBlend(self.ptr, allocator, device, command_buffer, first_attachment, blend);
}

pub fn setColorWrite(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    first_attachment: ngl.Cmd.ColorAttachmentIndex,
    write_masks: []const ngl.Cmd.ColorMask,
) void {
    self.vtable.setColorWrite(
        self.ptr,
        allocator,
        device,
        command_buffer,
        first_attachment,
        write_masks,
    );
}

pub fn setBlendConstants(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    constants: [4]f32,
) void {
    self.vtable.setBlendConstants(self.ptr, device, command_buffer, constants);
}

pub fn beginRendering(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    rendering: ngl.Cmd.Rendering,
) void {
    self.vtable.beginRendering(self.ptr, allocator, device, command_buffer, rendering);
}

pub fn endRendering(self: *Self, device: Device, command_buffer: CommandBuffer) void {
    self.vtable.endRendering(self.ptr, device, command_buffer);
}

pub fn draw(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) void {
    self.vtable.draw(
        self.ptr,
        device,
        command_buffer,
        vertex_count,
        instance_count,
        first_vertex,
        first_instance,
    );
}

pub fn drawIndexed(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    index_count: u32,
    instance_count: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32,
) void {
    self.vtable.drawIndexed(
        self.ptr,
        device,
        command_buffer,
        index_count,
        instance_count,
        first_index,
        vertex_offset,
        first_instance,
    );
}

pub fn drawIndirect(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    buffer: Buffer,
    offset: u64,
    draw_count: u32,
    stride: u32,
) void {
    self.vtable.drawIndirect(self.ptr, device, command_buffer, buffer, offset, draw_count, stride);
}

pub fn drawIndexedIndirect(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    buffer: Buffer,
    offset: u64,
    draw_count: u32,
    stride: u32,
) void {
    self.vtable.drawIndexedIndirect(
        self.ptr,
        device,
        command_buffer,
        buffer,
        offset,
        draw_count,
        stride,
    );
}

pub fn dispatch(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    group_count_x: u32,
    group_count_y: u32,
    group_count_z: u32,
) void {
    self.vtable.dispatch(
        self.ptr,
        device,
        command_buffer,
        group_count_x,
        group_count_y,
        group_count_z,
    );
}

pub fn dispatchIndirect(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    buffer: Buffer,
    offset: u64,
) void {
    self.vtable.dispatchIndirect(self.ptr, device, command_buffer, buffer, offset);
}

pub fn clearBuffer(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    buffer: Buffer,
    offset: u64,
    size: ?u64,
    value: u8,
) void {
    self.vtable.clearBuffer(self.ptr, device, command_buffer, buffer, offset, size, value);
}

pub fn copyBuffer(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    copies: []const ngl.Cmd.BufferCopy,
) void {
    self.vtable.copyBuffer(self.ptr, allocator, device, command_buffer, copies);
}

pub fn copyImage(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    copies: []const ngl.Cmd.ImageCopy,
) void {
    self.vtable.copyImage(self.ptr, allocator, device, command_buffer, copies);
}

pub fn copyBufferToImage(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    copies: []const ngl.Cmd.BufferImageCopy,
) void {
    self.vtable.copyBufferToImage(self.ptr, allocator, device, command_buffer, copies);
}

pub fn copyImageToBuffer(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    copies: []const ngl.Cmd.BufferImageCopy,
) void {
    self.vtable.copyImageToBuffer(self.ptr, allocator, device, command_buffer, copies);
}

pub fn resetQueryPool(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    query_pool: QueryPool,
    first_query: u32,
    query_count: u32,
) void {
    self.vtable.resetQueryPool(
        self.ptr,
        device,
        command_buffer,
        query_pool,
        first_query,
        query_count,
    );
}

pub fn beginQuery(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    query_type: ngl.QueryType,
    query_pool: QueryPool,
    query: u32,
    control: ngl.Cmd.QueryControl,
) void {
    self.vtable.beginQuery(
        self.ptr,
        device,
        command_buffer,
        query_type,
        query_pool,
        query,
        control,
    );
}

pub fn endQuery(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    query_type: ngl.QueryType,
    query_pool: QueryPool,
    query: u32,
) void {
    self.vtable.endQuery(self.ptr, device, command_buffer, query_type, query_pool, query);
}

pub fn writeTimestamp(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    stage: ngl.Stage,
    query_pool: QueryPool,
    query: u32,
) void {
    self.vtable.writeTimestamp(self.ptr, device, command_buffer, stage, query_pool, query);
}

pub fn copyQueryPoolResults(
    self: *Self,
    device: Device,
    command_buffer: CommandBuffer,
    query_type: ngl.QueryType,
    query_pool: QueryPool,
    first_query: u32,
    query_count: u32,
    dest: Buffer,
    dest_offset: u64,
    result: ngl.Cmd.QueryResult,
) void {
    self.vtable.copyQueryPoolResults(
        self.ptr,
        device,
        command_buffer,
        query_type,
        query_pool,
        first_query,
        query_count,
        dest,
        dest_offset,
        result,
    );
}

pub fn barrier(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    barriers: []const ngl.Cmd.Barrier,
) void {
    self.vtable.barrier(self.ptr, allocator, device, command_buffer, barriers);
}

pub fn executeCommands(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
    secondary_command_buffers: []const *ngl.CommandBuffer,
) void {
    self.vtable.executeCommands(
        self.ptr,
        allocator,
        device,
        command_buffer,
        secondary_command_buffers,
    );
}

pub fn endCommandBuffer(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    command_buffer: CommandBuffer,
) Error!void {
    try self.vtable.endCommandBuffer(self.ptr, allocator, device, command_buffer);
}

pub fn initFence(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.Fence.Desc,
) Error!Fence {
    return self.vtable.initFence(self.ptr, allocator, device, desc);
}

pub fn resetFences(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    fences: []const *ngl.Fence,
) Error!void {
    try self.vtable.resetFences(self.ptr, allocator, device, fences);
}

pub fn waitFences(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    timeout: u64,
    fences: []const *ngl.Fence,
) Error!void {
    try self.vtable.waitFences(self.ptr, allocator, device, timeout, fences);
}

pub fn getFenceStatus(self: *Self, device: Device, fence: Fence) Error!ngl.Fence.Status {
    return self.vtable.getFenceStatus(self.ptr, device, fence);
}

pub fn deinitFence(self: *Self, allocator: std.mem.Allocator, device: Device, fence: Fence) void {
    self.vtable.deinitFence(self.ptr, allocator, device, fence);
}

pub fn initSemaphore(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.Semaphore.Desc,
) Error!Semaphore {
    return self.vtable.initSemaphore(self.ptr, allocator, device, desc);
}

pub fn deinitSemaphore(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    semaphore: Semaphore,
) void {
    self.vtable.deinitSemaphore(self.ptr, allocator, device, semaphore);
}

pub fn getFormatFeatures(self: *Self, device: Device, format: ngl.Format) ngl.Format.FeatureSet {
    return self.vtable.getFormatFeatures(self.ptr, device, format);
}

pub fn initBuffer(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.Buffer.Desc,
) Error!Buffer {
    return self.vtable.initBuffer(self.ptr, allocator, device, desc);
}

pub fn getMemoryRequirementsBuffer(
    self: *Self,
    device: Device,
    buffer: Buffer,
) ngl.Memory.Requirements {
    return self.vtable.getMemoryRequirementsBuffer(self.ptr, device, buffer);
}

pub fn bindBuffer(
    self: *Self,
    device: Device,
    buffer: Buffer,
    memory: Memory,
    memory_offset: u64,
) Error!void {
    try self.vtable.bindBuffer(self.ptr, device, buffer, memory, memory_offset);
}

pub fn deinitBuffer(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    buffer: Buffer,
) void {
    self.vtable.deinitBuffer(self.ptr, allocator, device, buffer);
}

pub fn initBufferView(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.BufferView.Desc,
) Error!BufferView {
    return self.vtable.initBufferView(self.ptr, allocator, device, desc);
}

pub fn deinitBufferView(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    buffer_view: BufferView,
) void {
    self.vtable.deinitBufferView(self.ptr, allocator, device, buffer_view);
}

pub fn initImage(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.Image.Desc,
) Error!Image {
    return self.vtable.initImage(self.ptr, allocator, device, desc);
}

pub fn deinitImage(self: *Self, allocator: std.mem.Allocator, device: Device, image: Image) void {
    self.vtable.deinitImage(self.ptr, allocator, device, image);
}

pub fn getImageCapabilities(
    self: *Self,
    device: Device,
    @"type": ngl.Image.Type,
    format: ngl.Format,
    tiling: ngl.Image.Tiling,
    usage: ngl.Image.Usage,
    misc: ngl.Image.Misc,
) Error!ngl.Image.Capabilities {
    return self.vtable.getImageCapabilities(self.ptr, device, @"type", format, tiling, usage, misc);
}

pub fn getImageDataLayout(
    self: *Self,
    device: Device,
    image: Image,
    @"type": ngl.Image.Type,
    aspect: ngl.Image.Aspect,
    level: u32,
    layer: u32,
) ngl.Image.DataLayout {
    return self.vtable.getImageDataLayout(self.ptr, device, image, @"type", aspect, level, layer);
}

pub fn getMemoryRequirementsImage(
    self: *Self,
    device: Device,
    image: Image,
) ngl.Memory.Requirements {
    return self.vtable.getMemoryRequirementsImage(self.ptr, device, image);
}

pub fn bindImage(
    self: *Self,
    device: Device,
    image: Image,
    memory: Memory,
    memory_offset: u64,
) Error!void {
    try self.vtable.bindImage(self.ptr, device, image, memory, memory_offset);
}

pub fn initImageView(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.ImageView.Desc,
) Error!ImageView {
    return self.vtable.initImageView(self.ptr, allocator, device, desc);
}

pub fn deinitImageView(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    image_view: ImageView,
) void {
    self.vtable.deinitImageView(self.ptr, allocator, device, image_view);
}

pub fn initSampler(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.Sampler.Desc,
) Error!Sampler {
    return self.vtable.initSampler(self.ptr, allocator, device, desc);
}

pub fn deinitSampler(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    sampler: Sampler,
) void {
    self.vtable.deinitSampler(self.ptr, allocator, device, sampler);
}

pub fn initShader(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    descs: []const ngl.Shader.Desc,
    shaders: []Error!ngl.Shader,
) Error!void {
    try self.vtable.initShader(self.ptr, allocator, device, descs, shaders);
}

pub fn deinitShader(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    shader: Shader,
) void {
    self.vtable.deinitShader(self.ptr, allocator, device, shader);
}

pub fn initShaderLayout(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.ShaderLayout.Desc,
) Error!ShaderLayout {
    return self.vtable.initShaderLayout(self.ptr, allocator, device, desc);
}

pub fn deinitShaderLayout(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    shader_layout: ShaderLayout,
) void {
    self.vtable.deinitShaderLayout(self.ptr, allocator, device, shader_layout);
}

pub fn initDescriptorSetLayout(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.DescriptorSetLayout.Desc,
) Error!DescriptorSetLayout {
    return self.vtable.initDescriptorSetLayout(self.ptr, allocator, device, desc);
}

pub fn deinitDescriptorSetLayout(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    descriptor_set_layout: DescriptorSetLayout,
) void {
    self.vtable.deinitDescriptorSetLayout(self.ptr, allocator, device, descriptor_set_layout);
}

pub fn initDescriptorPool(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.DescriptorPool.Desc,
) Error!DescriptorPool {
    return self.vtable.initDescriptorPool(self.ptr, allocator, device, desc);
}

pub fn allocDescriptorSets(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    descriptor_pool: DescriptorPool,
    desc: ngl.DescriptorSet.Desc,
    descriptor_sets: []ngl.DescriptorSet,
) Error!void {
    try self.vtable.allocDescriptorSets(
        self.ptr,
        allocator,
        device,
        descriptor_pool,
        desc,
        descriptor_sets,
    );
}

pub fn resetDescriptorPool(
    self: *Self,
    device: Device,
    descriptor_pool: DescriptorPool,
) Error!void {
    try self.vtable.resetDescriptorPool(self.ptr, device, descriptor_pool);
}

pub fn deinitDescriptorPool(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    descriptor_pool: DescriptorPool,
) void {
    self.vtable.deinitDescriptorPool(self.ptr, allocator, device, descriptor_pool);
}

pub fn writeDescriptorSets(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    writes: []const ngl.DescriptorSet.Write,
) Error!void {
    try self.vtable.writeDescriptorSets(self.ptr, allocator, device, writes);
}

pub fn getQueryLayout(
    self: *Self,
    device: Device,
    query_type: ngl.QueryType,
    query_count: u32,
    with_availability: bool,
) ngl.QueryType.Layout {
    return self.vtable.getQueryLayout(self.ptr, device, query_type, query_count, with_availability);
}

pub fn initQueryPool(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.QueryPool.Desc,
) Error!QueryPool {
    return self.vtable.initQueryPool(self.ptr, allocator, device, desc);
}

pub fn deinitQueryPool(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    query_pool: QueryPool,
) void {
    self.vtable.deinitQueryPool(self.ptr, allocator, device, query_pool);
}

pub fn resolveQueryOcclusion(
    self: *Self,
    device: Device,
    first_result: u32,
    with_availability: bool,
    source: []const u8,
    dest: @TypeOf((ngl.QueryResolve(.occlusion){}).resolved_results),
) Error!void {
    try self.vtable.resolveQueryOcclusion(
        self.ptr,
        device,
        first_result,
        with_availability,
        source,
        dest,
    );
}

pub fn resolveQueryTimestamp(
    self: *Self,
    device: Device,
    first_result: u32,
    with_availability: bool,
    source: []const u8,
    dest: @TypeOf((ngl.QueryResolve(.timestamp){}).resolved_results),
) Error!void {
    try self.vtable.resolveQueryTimestamp(
        self.ptr,
        device,
        first_result,
        with_availability,
        source,
        dest,
    );
}

pub fn initSurface(
    self: *Self,
    allocator: std.mem.Allocator,
    desc: ngl.Surface.Desc,
) Error!Surface {
    return self.vtable.initSurface(self.ptr, allocator, desc);
}

pub fn isSurfaceCompatible(
    self: *Self,
    surface: Surface,
    gpu: ngl.Gpu,
    queue: ngl.Queue.Index,
) Error!bool {
    return self.vtable.isSurfaceCompatible(self.ptr, surface, gpu, queue);
}

pub fn getSurfacePresentModes(
    self: *Self,
    surface: Surface,
    gpu: ngl.Gpu,
) Error!ngl.Surface.PresentMode.Flags {
    return self.vtable.getSurfacePresentModes(self.ptr, surface, gpu);
}

pub fn getSurfaceFormats(
    self: *Self,
    allocator: std.mem.Allocator,
    surface: Surface,
    gpu: ngl.Gpu,
) Error![]ngl.Surface.Format {
    return self.vtable.getSurfaceFormats(self.ptr, allocator, surface, gpu);
}

pub fn getSurfaceCapabilities(
    self: *Self,
    surface: Surface,
    gpu: ngl.Gpu,
    present_mode: ngl.Surface.PresentMode,
) Error!ngl.Surface.Capabilities {
    return self.vtable.getSurfaceCapabilities(
        self.ptr,
        surface,
        gpu,
        present_mode,
    );
}

pub fn deinitSurface(self: *Self, allocator: std.mem.Allocator, surface: Surface) void {
    self.vtable.deinitSurface(self.ptr, allocator, surface);
}

pub fn initSwapchain(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    desc: ngl.Swapchain.Desc,
) Error!Swapchain {
    return self.vtable.initSwapchain(self.ptr, allocator, device, desc);
}

pub fn getSwapchainImages(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    swapchain: Swapchain,
) Error![]ngl.Image {
    return self.vtable.getSwapchainImages(self.ptr, allocator, device, swapchain);
}

pub fn nextSwapchainImage(
    self: *Self,
    device: Device,
    swapchain: Swapchain,
    timeout: u64,
    semaphore: ?Semaphore,
    fence: ?Fence,
) Error!ngl.Swapchain.Index {
    return self.vtable.nextSwapchainImage(self.ptr, device, swapchain, timeout, semaphore, fence);
}

pub fn deinitSwapchain(
    self: *Self,
    allocator: std.mem.Allocator,
    device: Device,
    swapchain: Swapchain,
) void {
    self.vtable.deinitSwapchain(self.ptr, allocator, device, swapchain);
}
