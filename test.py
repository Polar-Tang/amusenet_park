from diffusers import StableDiffusionPipeline
import torch
from PIL import Image

# Define device as it might not be defined if previous cells failed
if torch.cuda.is_available():
    device=torch.device("cuda")
elif torch.backends.mps.is_available():
    device=torch.device("mps")
else:
    device=torch.device("cpu")

model_id = "Qwen/Qwen-Image-2512"

# Load the entire pipeline directly
pipe = StableDiffusionPipeline.from_pretrained(model_id, torch_dtype=torch.float16)
pipe = pipe.to(device)

prompt = "a dragon flying over a city"

height = 512                        # default height of Stable Diffusion
width = 512                         # default width of Stable Diffusion

num_inference_steps = 100            # Number of denoising steps

guidance_scale = 7.5                # Scale for classifier-free guidance

generator = torch.Generator(device).manual_seed(32)   # Seed generator to create the inital latent noise

# Generate the image using the pipeline
image = pipe(
    prompt,
    height=height,
    width=width,
    num_inference_steps=num_inference_steps,
    guidance_scale=guidance_scale,
    generator=generator
).images[0]

# Display the image
image