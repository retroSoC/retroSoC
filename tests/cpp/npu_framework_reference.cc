// Host-only adapter to the dependency-locked TensorFlow Lite integer kernels.
// No NPU descriptors, packed constants, or NPU arithmetic enter this executable.
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>

#include "tensorflow/lite/kernels/internal/reference/integer_ops/conv.h"
#include "tensorflow/lite/kernels/internal/reference/integer_ops/depthwise_conv.h"
#include "tensorflow/lite/kernels/internal/reference/integer_ops/fully_connected.h"
#include "tensorflow/lite/kernels/internal/reference/integer_ops/pooling.h"
#include "tensorflow/lite/kernels/internal/reference/softmax.h"
#include "tensorflow/lite/kernels/padding.h"

namespace {
void require(bool ok, const char* message) {
  if (!ok) throw std::runtime_error(message);
}
uint32_t read32(std::istream& stream) {
  uint8_t b[4];
  stream.read(reinterpret_cast<char*>(b), 4);
  require(bool(stream), "truncated oracle input");
  return uint32_t(b[0]) | (uint32_t(b[1]) << 8) | (uint32_t(b[2]) << 16) |
         (uint32_t(b[3]) << 24);
}
int32_t read_signed(std::istream& stream) {
  uint32_t bits = read32(stream);
  int32_t value;
  std::memcpy(&value, &bits, sizeof(value));
  return value;
}
double read_double(std::istream& stream) {
  uint64_t bits = read32(stream);
  bits |= uint64_t(read32(stream)) << 32;
  double value;
  static_assert(sizeof(value) == sizeof(bits), "binary64 required");
  std::memcpy(&value, &bits, sizeof(value));
  require(std::isfinite(value), "nonfinite oracle scale/beta");
  return value;
}
void write32(std::ostream& stream, uint32_t value) {
  for (unsigned i = 0; i < 4; ++i) stream.put(char((value >> (8 * i)) & 255));
}
struct Tensor {
  tflite::RuntimeShape shape;
  std::vector<double> scales;
  std::vector<int32_t> zeros;
  std::vector<int8_t> data;
  int type;
};
struct Operator {
  int code;
  std::vector<uint32_t> inputs;
  uint32_t output;
  // padding, stride_h/w, dilation_h/w, depth_multiplier, filter_h/w, activation
  int p[9];
  double beta;
};
std::vector<uint32_t> indices(std::istream& stream, size_t tensors) {
  uint32_t count = read32(stream);
  require(count <= tensors, "too many tensor indices");
  std::vector<uint32_t> result;
  for (uint32_t i = 0; i < count; ++i) {
    uint32_t index = read32(stream);
    require(index < tensors, "tensor index out of range");
    result.push_back(index);
  }
  return result;
}
void activation(int kind, const Tensor& out, int32_t& lo, int32_t& hi) {
  require(out.scales.size() == 1 && out.scales[0] > 0 && out.zeros.size() == 1,
          "invalid output quantization");
  lo = -128;
  hi = 127;
  if (kind == 1 || kind == 3) lo = std::max(-128, out.zeros[0]);
  if (kind == 3)
    hi = std::min(127, int(tflite::TfLiteRound(6.0 / out.scales[0])) + out.zeros[0]);
  require(kind == 0 || kind == 1 || kind == 3, "unsupported fused activation");
}
void execute(const Operator& op, std::vector<Tensor>& tensors) {
  Tensor& out = tensors.at(op.output);
  const Tensor& in = tensors.at(op.inputs.at(0));
  require(in.type == 9 && out.type == 9, "non INT8 activation");
  if (op.code == 22) {
    require(in.shape.FlatSize() == out.shape.FlatSize(), "invalid reshape");
    out.data = in.data;
    return;
  }
  int32_t lo, hi;
  activation(op.p[8], out, lo, hi);
  out.data.resize(out.shape.FlatSize());
  if (op.code == 25) {
    require(in.scales.size() == 1 && in.scales[0] > 0 && op.beta > 0,
            "invalid softmax input quantization");
    require(out.scales[0] == 1.0 / 256 && out.zeros[0] == -128,
            "invalid softmax output quantization");
    require(op.beta * in.scales[0] * (1 << 26) > 1, "softmax multiplier too small");
    tflite::SoftmaxParams p{};
    tflite::PreprocessSoftmaxScaling(op.beta, in.scales[0], 5,
                                   &p.input_multiplier, &p.input_left_shift);
    p.diff_min = -tflite::CalculateInputRadius(5, p.input_left_shift);
    tflite::reference_ops::Softmax(p, in.shape, in.data.data(), out.shape, out.data.data());
    return;
  }
  if (op.code == 1) {
    require(in.scales == out.scales && in.zeros == out.zeros, "pool quantization drift");
    tflite::PoolParams p{};
    p.stride_height = op.p[1]; p.stride_width = op.p[2];
    p.filter_height = op.p[6]; p.filter_width = op.p[7];
    int oh, ow;
    auto pad = tflite::ComputePaddingHeightWidth(
        p.stride_height, p.stride_width, 1, 1, in.shape.Dims(1), in.shape.Dims(2),
        p.filter_height, p.filter_width, op.p[0] == 0 ? kTfLitePaddingSame : kTfLitePaddingValid,
        &oh, &ow);
    require(oh == out.shape.Dims(1) && ow == out.shape.Dims(2), "pool output geometry drift");
    p.padding_values.height = pad.height; p.padding_values.width = pad.width;
    p.quantized_activation_min = lo; p.quantized_activation_max = hi;
    tflite::reference_integer_ops::AveragePool(p, in.shape, in.data.data(), out.shape,
                                             out.data.data());
    return;
  }
  require(op.inputs.size() == 3, "weighted operator needs input/weight/bias");
  const Tensor& weights = tensors.at(op.inputs[1]);
  const Tensor& bias = tensors.at(op.inputs[2]);
  const int channels = out.shape.Dims(out.shape.DimensionsCount() - 1);
  require(weights.type == 9 && bias.type == 2, "invalid constant types");
  require(bias.data.size() == size_t(channels) * 4, "invalid bias size");
  std::vector<int32_t> biases(channels), multipliers(channels), shifts(channels);
  for (int c = 0; c < channels; ++c) {
    uint32_t bits = 0;
    for (unsigned k = 0; k < 4; ++k)
      bits |= uint32_t(uint8_t(bias.data[4 * c + k])) << (8 * k);
    std::memcpy(&biases[c], &bits, 4);
    double scale = weights.scales.at(weights.scales.size() == 1 ? 0 : c);
    require(scale > 0, "invalid weight scale");
    tflite::QuantizeMultiplier(in.scales.at(0) * scale / out.scales.at(0),
                              &multipliers[c], &shifts[c]);
  }
  for (auto zero : weights.zeros) require(zero == 0, "non symmetric weights");
  if (op.code == 9) {
    require(weights.scales.size() == 1, "fixed-model FC oracle requires per-tensor scale");
    tflite::FullyConnectedParams p{};
    p.input_offset = -in.zeros.at(0); p.output_offset = out.zeros.at(0);
    p.output_multiplier = multipliers[0]; p.output_shift = shifts[0];
    p.quantized_activation_min = lo; p.quantized_activation_max = hi;
    tflite::reference_integer_ops::FullyConnected(
        p, in.shape, in.data.data(), weights.shape, weights.data.data(), bias.shape,
        biases.data(), out.shape, out.data.data());
    return;
  }
  require(op.code == 3 || op.code == 4, "unsupported fixed-model operator");
  int oh, ow;
  auto pad = tflite::ComputePaddingHeightWidth(
      op.p[1], op.p[2], op.p[3], op.p[4], in.shape.Dims(1), in.shape.Dims(2),
      weights.shape.Dims(1), weights.shape.Dims(2),
      op.p[0] == 0 ? kTfLitePaddingSame : kTfLitePaddingValid, &oh, &ow);
  require(oh == out.shape.Dims(1) && ow == out.shape.Dims(2), "conv output geometry drift");
  if (op.code == 3) {
    tflite::ConvParams p{};
    p.input_offset = -in.zeros.at(0); p.output_offset = out.zeros.at(0);
    p.stride_height = op.p[1]; p.stride_width = op.p[2];
    p.dilation_height_factor = op.p[3]; p.dilation_width_factor = op.p[4];
    p.padding_values.height = pad.height; p.padding_values.width = pad.width;
    p.quantized_activation_min = lo; p.quantized_activation_max = hi;
    tflite::reference_integer_ops::ConvPerChannel(
        p, multipliers.data(), shifts.data(), in.shape, in.data.data(), weights.shape,
        weights.data.data(), bias.shape, biases.data(), out.shape, out.data.data());
  } else {
    tflite::DepthwiseParams p{};
    p.input_offset = -in.zeros.at(0); p.output_offset = out.zeros.at(0);
    p.stride_height = op.p[1]; p.stride_width = op.p[2];
    p.dilation_height_factor = op.p[3]; p.dilation_width_factor = op.p[4];
    p.depth_multiplier = op.p[5];
    p.padding_values.height = pad.height; p.padding_values.width = pad.width;
    p.quantized_activation_min = lo; p.quantized_activation_max = hi;
    tflite::reference_integer_ops::DepthwiseConvPerChannel(
        p, multipliers.data(), shifts.data(), in.shape, in.data.data(), weights.shape,
        weights.data.data(), bias.shape, biases.data(), out.shape, out.data.data());
  }
}
void model_run(const char* model, const char* input, const char* output) {
  std::ifstream stream(model, std::ios::binary);
  require(read32(stream) == 0x314d504e, "invalid oracle model magic");
  const uint32_t count = read32(stream);
  require(count > 0 && count <= 4096, "invalid tensor count");
  std::vector<Tensor> tensors(count);
  for (auto& t : tensors) {
    const uint32_t rank = read32(stream);
    require(rank > 0 && rank <= 4, "invalid tensor rank");
    t.shape.Resize(rank);
    uint64_t size = 1;
    for (uint32_t d = 0; d < rank; ++d) {
      const uint32_t dim = read32(stream);
      require(dim > 0 && dim <= 4096, "invalid tensor dimension");
      t.shape.SetDim(d, dim); size *= dim;
    }
    require(size <= 16 * 1024 * 1024, "oracle tensor too large");
    t.type = read32(stream);
    require(t.type == 9 || t.type == 2, "unsupported tensor type");
    uint32_t n = read32(stream);
    require(n <= 4096, "too many scales");
    for (uint32_t i = 0; i < n; ++i) t.scales.push_back(read_double(stream));
    n = read32(stream);
    require(n <= 4096, "too many zero points");
    for (uint32_t i = 0; i < n; ++i) t.zeros.push_back(read_signed(stream));
    n = read32(stream);
    require(n == 0 || n == size * (t.type == 2 ? 4 : 1), "constant size mismatch");
    t.data.resize(size * (t.type == 2 ? 4 : 1));
    stream.read(reinterpret_cast<char*>(t.data.data()), n);
    require(bool(stream), "truncated constant");
  }
  auto inputs = indices(stream, count);
  require(inputs.size() == 1, "fixed models require one input");
  const uint32_t num_ops = read32(stream);
  require(num_ops > 0 && num_ops <= 4096, "invalid operator count");
  std::vector<Operator> ops(num_ops);
  uint32_t emitted = 0;
  for (auto& op : ops) {
    op.code = read32(stream); op.inputs = indices(stream, count);
    require(!op.inputs.empty(), "operator has no inputs");
    auto outputs = indices(stream, count);
    require(outputs.size() == 1, "operator must have one output");
    op.output = outputs[0];
    for (auto& p : op.p) p = read_signed(stream);
    op.beta = read_double(stream);
    if (op.code != 22) ++emitted;
  }
  require(stream.peek() == EOF, "trailing model bytes");
  std::ifstream image(input, std::ios::binary);
  auto& data = tensors[inputs[0]].data;
  image.read(reinterpret_cast<char*>(data.data()), data.size());
  require(bool(image) && image.peek() == EOF, "input byte count mismatch");
  std::ofstream result(output, std::ios::binary);
  write32(result, 0x314f504e); write32(result, emitted);
  for (auto& op : ops) {
    execute(op, tensors);
    if (op.code == 22) continue;
    const auto& t = tensors[op.output];
    write32(result, op.output); write32(result, t.data.size());
    result.write(reinterpret_cast<const char*>(t.data.data()), t.data.size());
  }
  result.flush(); require(bool(result), "oracle output write failed");
}
}  // namespace

int main(int argc, char** argv) {
  try {
    require(argc == 4, "usage: oracle MODEL INPUT OUTPUT");
    model_run(argv[1], argv[2], argv[3]);
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "oracle error: " << error.what() << '\n';
    return 1;
  }
}
