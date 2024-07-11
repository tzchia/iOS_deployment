from coremltools.models import MLModel
from coremltools.optimize.coreml import get_weights_metadata


# Load your CoreML model
model = MLModel('models/flip_v_0322.mlpackage')
weight_metadata_dict = get_weights_metadata(model, weight_threshold=2048)
# print(weight_metadata_dict.keys()) # ['backbone_vit_conv1_weight', 'backbone_vit_transformer_resblocks_0_attn_out_proj_weight', ..., 'embedder_bottleneck_layer_fc_weight', 'op_53']
print(weight_metadata_dict['embedder_bottleneck_layer_fc_weight'].val)

'''
embedder_bottleneck_layer_fc_weight: (512, 768)
op_53: (197, 768)
'''