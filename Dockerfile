# Stage 1: Base image with common dependencies
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 as base

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1 
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.10 \
    python3-pip \
    git \
    wget \
    libgl1 \
    && ln -sf /usr/bin/python3.10 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install comfy-cli
RUN pip install comfy-cli

# Install ComfyUI
RUN /usr/bin/yes | comfy --workspace /comfyui install --cuda-version 11.8 --nvidia --version 0.3.26

# Change working directory to ComfyUI
WORKDIR /comfyui

# Install runpod
RUN pip install runpod requests

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Add scripts
ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
RUN chmod +x /start.sh /restore_snapshot.sh

# Optionally copy the snapshot file
ADD *snapshot*.json /

# Restore the snapshot to install custom nodes
RUN /restore_snapshot.sh

# Start container
CMD ["/start.sh"]

# Stage 2: Download models
FROM base as downloader

ARG HUGGINGFACE_ACCESS_TOKEN
ARG MODEL_TYPE

# Change working directory to ComfyUI
WORKDIR /comfyui

# Create necessary directories
RUN mkdir -p models/checkpoints models/vae models/LLM models/LLM/Florence-2-base models/CatVTON models/CatVTON/sd-vae-ft-mse models/CatVTON/stable-diffusion-inpainting models/CatVTON/stable-diffusion-inpainting/scheduler models/CatVTON/stable-diffusion-inpainting/unet models/CatVTON/mix-48k-1024 models/CatVTON/mix-48k-1024/attention

# Download checkpoints/vae/LoRA to include in image based on model type
RUN wget -O models/CatVTON/sd-vae-ft-mse/diffusion_pytorch_model.safetensors https://drive.google.com/file/d/1Hs5THjD-Pzj2p13aFOnK3X6rzIEN2KtJ/view?usp=drive_link && \
    wget -O models/CatVTON/sd-vae-ft-mse/config.json https://drive.google.com/file/d/1av0d0CR5vs8qEmtzoh2rSkTr049gh3Kh/view?usp=drive_link && \
    wget -O models/CatVTON/stable-diffusion-inpainting/scheduler/scheduler_config.json https://drive.google.com/file/d/1VSA84CHmcoWPSz-ro7mJwWB1I2Oknd5A/view?usp=drive_link && \
    wget -O models/CatVTON/stable-diffusion-inpainting/unet/diffusion_pytorch_model.safetensors https://drive.google.com/file/d/1TrB_f7a95xmRf8MGBs2LepUERhC-lXuP/view?usp=drive_link && \
    wget -O models/CatVTON/stable-diffusion-inpainting/unet/config.json https://drive.google.com/file/d/1ZY982pH1fhu0g7heea2agvHT4H39ARn3/view?usp=drive_link && \
    wget -O models/CatVTON/mix-48k-1024/attention/model.safetensorshttps://drive.google.com/file/d/1vopPat6_hW0ZD53hFGVR6K94gAnWmt-c/view?usp=drive_link

RUN git clone https://huggingface.co/microsoft/Florence-2-base models/LLM/Florence-2-base

# Stage 3: Final image
FROM base as final

# Copy models from stage 2 to the final image
COPY --from=downloader /comfyui/models /comfyui/models

# Start container
CMD ["/start.sh"]