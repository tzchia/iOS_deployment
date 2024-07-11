import coremltools as ct, numpy as np, torch, sys
sys.path.append('/Users/tc/Program/passive_face_anti-spoofing/FLIP')
from fas_cpu import flip_v_1out


net1 = flip_v_1out().to('cpu')
ckpt = torch.load('/Users/tc/Program/passive_face_anti-spoofing/FLIP/log/0531/424/allflip_v_checkpoint_run_0.pth.tar', map_location=torch.device('cpu'))
# print(ckpt['epoch'], ckpt['valid_arg']); exit()
net1.load_state_dict(ckpt["state_dict"])
net1.eval() # To ensure that operations such as dropout are disabled, it’s important to set the model to evaluation mode (not training mode) before tracing. This setting also results in a more optimized version of the model for conversion.
example_input = torch.randn(1, 3, 224, 224) # 1, 3, 224, 224
traced_model = torch.jit.trace(net1, example_input) # enter `forward`


# preprocessing
scale = 1/(0.226*255.0) # (0.226*255.0) 1/255.0
bias = [- 0.485/(0.229) , - 0.456/(0.224), - 0.406/(0.225)]
image_input = ct.ImageType(
    name="image",
    shape=example_input.shape,
    scale=scale, bias=bias,
    color_layout=ct.colorlayout.RGB, # RGB. BGR
    #     dtype=np.float32 # TypeError: __init__() got an unexpected keyword argument 'dtype'
)
# tensor_input = ct.TensorType(
#     name="image",
#     shape=example_input.shape,
#     # scale=scale, bias=bias, # TypeError: __init__() got an unexpected keyword argument 'scale'
#     dtype=np.float32
# )

model = ct.convert(
    traced_model,
    convert_to="mlprogram", # mlprogram, neuralnetwork
    inputs=[image_input], # [tensor_input], [image_input]
    # preprocessing_args={"image": preprocess_image},
    source="pytorch", 
    minimum_deployment_target=ct.target.iOS15, # iOS15, iOS13
    compute_precision=ct.precision.FLOAT16, # FLOAT16, FLOAT32
    )

model.save("models/0606_424_0531_float16.mlpackage") # .mlpackage, .mlmodel
# TypeError: @model must either be a PyTorch .pt or .pth file or a TorchScript object, received: <class 'fas_cpu.flip_v'>