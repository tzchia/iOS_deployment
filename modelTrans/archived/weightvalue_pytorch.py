import sys
sys.path.append('/Users/tc/Program/passive_face_anti-spoofing/FLIP')
import torch
from fas_cpu import flip_v_1out

net1 = flip_v_1out().to('cpu')
ckpt = torch.load('/Users/tc/Program/passive_face_anti-spoofing/FLIP/log/0322/Tsq/v/teamflip_v_checkpoint_run_0.pth.tar', map_location=torch.device('cpu')) # /Users/tc/Program/passive_face_anti-spoofing/FLIP/log/0319/T/v/teamflip_v_checkpoint_run_4.pth
net1.load_state_dict(ckpt["state_dict"])

print(net1.embedder.bottleneck_layer_fc.weight)

'''
embedder.bottleneck_layer_fc
embedder.bottleneck_layer
classifier.classifier_layer: [2, 512]
'''