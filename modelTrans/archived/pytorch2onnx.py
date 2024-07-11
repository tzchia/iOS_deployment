import sys, torch, torchvision
sys.path.append('/Users/tc/Program/passive_face_anti-spoofing/FLIP')
from fas_cpu import flip_v

model = flip_v().to('cpu')
ckpt = torch.load('/Users/tc/Program/passive_face_anti-spoofing/FLIP/log/0319/T/v/teamflip_v_checkpoint_run_4.pth.tar', map_location=torch.device('cpu'))
model.load_state_dict(ckpt["state_dict"])

# Load your PyTorch model
# model = torchvision.models.resnet18(pretrained=True)
# model.eval()

# Create example input
dummy_input = torch.randn(1, 3, 224, 224)

# Export the model to ONNX
torch.onnx.export(model, dummy_input, "flip_v.onnx", verbose=True)