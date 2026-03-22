const std = @import("std");
const math = @import("math.zig");
const Vec3 = math.Vec3;
const render = @import("render.zig");
const vk = @import("vulkan");

const PushConstants = extern struct {
    width: u32,
    height: u32,
    samples_per_pixel: u32,
    seed: u32,
    fractal_type: u32,
    max_iterations: u32,
    power: f32,
    bailout: f32,
    fscale: f32,
    offset_x: f32,
    offset_y: f32,
    offset_z: f32,
    julia_cx: f32,
    julia_cy: f32,
    julia_cz: f32,
    cam_pos_x: f32,
    cam_pos_y: f32,
    cam_pos_z: f32,
    cam_fwd_x: f32,
    cam_fwd_y: f32,
    cam_fwd_z: f32,
    cam_right_x: f32,
    cam_right_y: f32,
    cam_right_z: f32,
    cam_up_x: f32,
    cam_up_y: f32,
    cam_up_z: f32,
    cam_fov: f32,
    cam_aspect: f32,
    roughness: f32,
    metallic: f32,
    emission: f32,
    exposure: f32,
    fog_density: f32,
    color_phase1: f32 = 0,
    color_phase2: f32 = 0,
};

extern fn vkGetInstanceProcAddr(instance: vk.Instance, p_name: [*:0]const u8) ?*const fn () callconv(.c) void;

pub const VulkanCompute = struct {
    vki: vk.InstanceWrapper,
    vkd: vk.DeviceWrapper,
    instance: vk.Instance,
    device: vk.Device,
    compute_queue: vk.Queue,
    output_buffer: vk.Buffer,
    output_memory: vk.DeviceMemory,
    descriptor_set_layout: vk.DescriptorSetLayout,
    pipeline_layout: vk.PipelineLayout,
    pipeline: vk.Pipeline,
    descriptor_pool: vk.DescriptorPool,
    descriptor_set: vk.DescriptorSet,
    command_pool: vk.CommandPool,
    command_buffer: vk.CommandBuffer,
    buffer_size: vk.DeviceSize,

    pub fn init(width: u32, height: u32) !VulkanCompute {
        const spv = @embedFile("pathtracer_spv");

        const vkb = vk.BaseWrapper.load(vkGetInstanceProcAddr);

        const portability_ext: [*:0]const u8 = "VK_KHR_portability_enumeration";
        const instance = try vkb.createInstance(&.{
            .flags = .{ .enumerate_portability_bit_khr = true },
            .p_application_info = &.{
                .p_application_name = "schism",
                .application_version = @bitCast(vk.makeApiVersion(0, 0, 1, 0)),
                .p_engine_name = "schism",
                .engine_version = @bitCast(vk.makeApiVersion(0, 0, 1, 0)),
                .api_version = @bitCast(vk.API_VERSION_1_2),
            },
            .enabled_extension_count = 1,
            .pp_enabled_extension_names = @ptrCast(&portability_ext),
        }, null);
        const vki = vk.InstanceWrapper.load(instance, vkGetInstanceProcAddr);
        errdefer vki.destroyInstance(instance, null);

        var device_count: u32 = 0;
        _ = try vki.enumeratePhysicalDevices(instance, &device_count, null);
        if (device_count == 0) return error.NoVulkanDevice;

        var devices_buf: [16]vk.PhysicalDevice = undefined;
        var actual_count: u32 = @min(device_count, 16);
        _ = try vki.enumeratePhysicalDevices(instance, &actual_count, &devices_buf);
        const devices = devices_buf[0..actual_count];

        var chosen_device = devices[0];
        for (devices) |dev| {
            const props = vki.getPhysicalDeviceProperties(dev);
            if (props.device_type == .discrete_gpu) {
                chosen_device = dev;
                break;
            }
        }

        const mem_properties = vki.getPhysicalDeviceMemoryProperties(chosen_device);

        var qf_count: u32 = 0;
        vki.getPhysicalDeviceQueueFamilyProperties(chosen_device, &qf_count, null);
        var qf_buf: [16]vk.QueueFamilyProperties = undefined;
        var actual_qf: u32 = @min(qf_count, 16);
        vki.getPhysicalDeviceQueueFamilyProperties(chosen_device, &actual_qf, &qf_buf);

        var compute_family: ?u32 = null;
        for (qf_buf[0..actual_qf], 0..) |qf, i| {
            if (qf.queue_flags.compute_bit) {
                compute_family = @intCast(i);
                break;
            }
        }
        const queue_family = compute_family orelse return error.NoComputeQueue;

        const queue_priority = [_]f32{1.0};
        const device = try vki.createDevice(chosen_device, &.{
            .queue_create_info_count = 1,
            .p_queue_create_infos = &[_]vk.DeviceQueueCreateInfo{.{
                .queue_family_index = queue_family,
                .queue_count = 1,
                .p_queue_priorities = &queue_priority,
            }},
        }, null);
        const get_device_proc = vki.dispatch.vkGetDeviceProcAddr orelse return error.NoDeviceProcAddr;
        const vkd = vk.DeviceWrapper.load(device, get_device_proc);
        errdefer vkd.destroyDevice(device, null);

        const compute_queue = vkd.getDeviceQueue(device, queue_family, 0);

        const buffer_size: vk.DeviceSize = @as(vk.DeviceSize, width) * height * 4 * @sizeOf(f32);
        const output_buffer = try vkd.createBuffer(device, &.{
            .size = buffer_size,
            .usage = .{ .storage_buffer_bit = true },
            .sharing_mode = .exclusive,
        }, null);

        const mem_req = vkd.getBufferMemoryRequirements(device, output_buffer);
        const mem_type_idx = findMemoryType(mem_properties, mem_req.memory_type_bits, .{
            .host_visible_bit = true,
            .host_coherent_bit = true,
        }) orelse return error.NoSuitableMemory;

        const output_memory = try vkd.allocateMemory(device, &.{
            .allocation_size = mem_req.size,
            .memory_type_index = mem_type_idx,
        }, null);
        try vkd.bindBufferMemory(device, output_buffer, output_memory, 0);

        const desc_layout = try vkd.createDescriptorSetLayout(device, &.{
            .binding_count = 1,
            .p_bindings = &[_]vk.DescriptorSetLayoutBinding{.{
                .binding = 0,
                .descriptor_type = .storage_buffer,
                .descriptor_count = 1,
                .stage_flags = .{ .compute_bit = true },
            }},
        }, null);

        const pipeline_layout = try vkd.createPipelineLayout(device, &.{
            .set_layout_count = 1,
            .p_set_layouts = &[_]vk.DescriptorSetLayout{desc_layout},
            .push_constant_range_count = 1,
            .p_push_constant_ranges = &[_]vk.PushConstantRange{.{
                .stage_flags = .{ .compute_bit = true },
                .offset = 0,
                .size = @sizeOf(PushConstants),
            }},
        }, null);

        const shader_module = try vkd.createShaderModule(device, &.{
            .code_size = spv.len,
            .p_code = @ptrCast(@alignCast(spv.ptr)),
        }, null);
        defer vkd.destroyShaderModule(device, shader_module, null);

        var pipeline: vk.Pipeline = undefined;
        _ = try vkd.createComputePipelines(device, .null_handle, 1, &[_]vk.ComputePipelineCreateInfo{.{
            .stage = .{
                .stage = .{ .compute_bit = true },
                .module = shader_module,
                .p_name = "main",
            },
            .layout = pipeline_layout,
            .base_pipeline_index = -1,
        }}, null, @ptrCast(&pipeline));

        const desc_pool = try vkd.createDescriptorPool(device, &.{
            .max_sets = 1,
            .pool_size_count = 1,
            .p_pool_sizes = &[_]vk.DescriptorPoolSize{.{
                .type = .storage_buffer,
                .descriptor_count = 1,
            }},
        }, null);

        var desc_set: vk.DescriptorSet = undefined;
        try vkd.allocateDescriptorSets(device, &.{
            .descriptor_pool = desc_pool,
            .descriptor_set_count = 1,
            .p_set_layouts = &[_]vk.DescriptorSetLayout{desc_layout},
        }, @ptrCast(&desc_set));

        const buffer_info = [_]vk.DescriptorBufferInfo{.{
            .buffer = output_buffer,
            .offset = 0,
            .range = buffer_size,
        }};
        vkd.updateDescriptorSets(device, 1, &[_]vk.WriteDescriptorSet{.{
            .dst_set = desc_set,
            .dst_binding = 0,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = .storage_buffer,
            .p_image_info = undefined,
            .p_buffer_info = &buffer_info,
            .p_texel_buffer_view = undefined,
        }}, 0, undefined);

        const cmd_pool = try vkd.createCommandPool(device, &.{
            .queue_family_index = queue_family,
        }, null);

        var cmd_buf: vk.CommandBuffer = undefined;
        try vkd.allocateCommandBuffers(device, &.{
            .command_pool = cmd_pool,
            .level = .primary,
            .command_buffer_count = 1,
        }, @ptrCast(&cmd_buf));

        return .{
            .vki = vki,
            .vkd = vkd,
            .instance = instance,
            .device = device,
            .compute_queue = compute_queue,
            .output_buffer = output_buffer,
            .output_memory = output_memory,
            .descriptor_set_layout = desc_layout,
            .pipeline_layout = pipeline_layout,
            .pipeline = pipeline,
            .descriptor_pool = desc_pool,
            .descriptor_set = desc_set,
            .command_pool = cmd_pool,
            .command_buffer = cmd_buf,
            .buffer_size = buffer_size,
        };
    }

    pub fn dispatch(self: *VulkanCompute, config: render.RenderConfig, seed_value: u32) !void {
        const pc = buildPushConstants(config, seed_value);
        const cmd = self.command_buffer;

        try self.vkd.beginCommandBuffer(cmd, &.{
            .flags = .{ .one_time_submit_bit = true },
        });

        self.vkd.cmdBindPipeline(cmd, .compute, self.pipeline);
        self.vkd.cmdBindDescriptorSets(cmd, .compute, self.pipeline_layout, 0, 1, &[_]vk.DescriptorSet{self.descriptor_set}, 0, undefined);
        self.vkd.cmdPushConstants(cmd, self.pipeline_layout, .{ .compute_bit = true }, 0, @sizeOf(PushConstants), &std.mem.toBytes(pc));

        const groups_x = (config.width + 15) / 16;
        const groups_y = (config.height + 15) / 16;
        self.vkd.cmdDispatch(cmd, groups_x, groups_y, 1);

        self.vkd.cmdPipelineBarrier(cmd, .{ .compute_shader_bit = true }, .{ .host_bit = true }, .{}, 1, &[_]vk.MemoryBarrier{.{
            .src_access_mask = .{ .shader_write_bit = true },
            .dst_access_mask = .{ .host_read_bit = true },
        }}, 0, undefined, 0, undefined);

        try self.vkd.endCommandBuffer(cmd);

        try self.vkd.queueSubmit(self.compute_queue, 1, &[_]vk.SubmitInfo{.{
            .command_buffer_count = 1,
            .p_command_buffers = &[_]vk.CommandBuffer{cmd},
        }}, .null_handle);

        try self.vkd.queueWaitIdle(self.compute_queue);
    }

    pub fn readPixels(self: *VulkanCompute, width: u32, height: u32) ![]Vec3 {
        const pixel_count = @as(usize, width) * height;
        const pixels = try std.heap.page_allocator.alloc(Vec3, pixel_count);

        const data = try self.vkd.mapMemory(self.device, self.output_memory, 0, self.buffer_size, .{});
        const float_data: [*]const f32 = @ptrCast(@alignCast(data));

        for (0..pixel_count) |i| {
            pixels[i] = .{
                .x = float_data[i * 4 + 0],
                .y = float_data[i * 4 + 1],
                .z = float_data[i * 4 + 2],
            };
        }

        self.vkd.unmapMemory(self.device, self.output_memory);
        return pixels;
    }

    pub fn deinit(self: *VulkanCompute) void {
        self.vkd.deviceWaitIdle(self.device) catch {};
        self.vkd.destroyCommandPool(self.device, self.command_pool, null);
        self.vkd.destroyDescriptorPool(self.device, self.descriptor_pool, null);
        self.vkd.destroyPipeline(self.device, self.pipeline, null);
        self.vkd.destroyPipelineLayout(self.device, self.pipeline_layout, null);
        self.vkd.destroyDescriptorSetLayout(self.device, self.descriptor_set_layout, null);
        self.vkd.freeMemory(self.device, self.output_memory, null);
        self.vkd.destroyBuffer(self.device, self.output_buffer, null);
        self.vkd.destroyDevice(self.device, null);
        self.vki.destroyInstance(self.instance, null);
    }
};

fn buildPushConstants(config: render.RenderConfig, seed_value: u32) PushConstants {
    return .{
        .width = config.width,
        .height = config.height,
        .samples_per_pixel = config.samples_per_pixel,
        .seed = seed_value,
        .fractal_type = @intFromEnum(config.fractal.fractal_type),
        .max_iterations = config.fractal.max_iterations,
        .power = @floatCast(config.fractal.power),
        .bailout = @floatCast(config.fractal.bailout),
        .fscale = @floatCast(config.fractal.scale),
        .offset_x = @floatCast(config.fractal.offset.x),
        .offset_y = @floatCast(config.fractal.offset.y),
        .offset_z = @floatCast(config.fractal.offset.z),
        .julia_cx = @floatCast(config.fractal.julia_c.x),
        .julia_cy = @floatCast(config.fractal.julia_c.y),
        .julia_cz = @floatCast(config.fractal.julia_c.z),
        .cam_pos_x = @floatCast(config.camera.position.x),
        .cam_pos_y = @floatCast(config.camera.position.y),
        .cam_pos_z = @floatCast(config.camera.position.z),
        .cam_fwd_x = @floatCast(config.camera.forward.x),
        .cam_fwd_y = @floatCast(config.camera.forward.y),
        .cam_fwd_z = @floatCast(config.camera.forward.z),
        .cam_right_x = @floatCast(config.camera.right.x),
        .cam_right_y = @floatCast(config.camera.right.y),
        .cam_right_z = @floatCast(config.camera.right.z),
        .cam_up_x = @floatCast(config.camera.up.x),
        .cam_up_y = @floatCast(config.camera.up.y),
        .cam_up_z = @floatCast(config.camera.up.z),
        .cam_fov = @floatCast(config.camera.fov),
        .cam_aspect = @floatCast(config.camera.aspect),
        .roughness = @floatCast(config.material.roughness),
        .metallic = @floatCast(config.material.metallic),
        .emission = @floatCast(config.material.emission),
        .exposure = @floatCast(config.exposure),
        .fog_density = @floatCast(config.fog_density),
        .color_phase1 = seedToPhase(seed_value, 0),
        .color_phase2 = seedToPhase(seed_value, 1),
    };
}

fn seedToPhase(seed: u32, offset: u32) f32 {
    var h = seed +% offset *% 2654435761;
    h ^= h >> 16;
    h *%= 0x45d9f3b;
    h ^= h >> 16;
    return @as(f32, @floatFromInt(h % 628)) / 100.0;
}

fn findMemoryType(
    mem_props: vk.PhysicalDeviceMemoryProperties,
    type_filter: u32,
    properties: vk.MemoryPropertyFlags,
) ?u32 {
    for (0..mem_props.memory_type_count) |i| {
        const idx: u5 = @intCast(i);
        if (type_filter & (@as(u32, 1) << idx) != 0) {
            const flags = mem_props.memory_types[i].property_flags;
            if (flags.host_visible_bit == properties.host_visible_bit and
                flags.host_coherent_bit == properties.host_coherent_bit)
            {
                return @intCast(i);
            }
        }
    }
    return null;
}
