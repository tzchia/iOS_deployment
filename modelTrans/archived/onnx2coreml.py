import coremltools as ct

# Convert ONNX model to CoreML
model = ct.converters.onnx.convert(model="flip_v.onnx", minimum_ios_deployment_target='13')
model.save("flip_v.mlmodel")