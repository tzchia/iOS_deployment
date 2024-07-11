import coremltools as ct

# Load the original model
spec = ct.models.utils.load_spec("models/_0702_mcl_run0_long.mlpackage")

# Add a softmax layer to the neural network
softmax_layer = spec.neuralNetworkClassifier.layers.add()
softmax_layer.name = "softmax"
softmax_layer.softmax.MergeFromString(b"")
softmax_layer.input.append("output_r")  # Change the output name to the name of the last layer.
softmax_layer.output.append("classLabelProbs")  # Specify the output name of the softmax layer

# Save the modified spec as new_mobile_coreML.mlmodel
ct.utils.save_spec(spec, "models/_0702_mcl_run0_long_softmax.mlpackage")