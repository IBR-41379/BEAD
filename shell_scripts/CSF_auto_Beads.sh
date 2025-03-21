#!/bin/bash --login
# Full CSF Job Submission Script for BEAD Anomaly Detection (f@pou compliant)

# # --- Step 1: Log into CSF ---
# # Replace <username> with your CSF username
# read -p "Enter your username: " username
# echo "Logging into CSF..." #Conidering we are logging in from on-campus
# ssh "$username@csf3.itservices.manchester.ac.uk" #After this, give your passcode and follow the 2FA steps
# # --Automating with 2FA is complex which need some trial and error.--
# # --Unfortunately, I do not have access to the CSF so I cannot confirm.-- 
# # --But I do think the above solution will not work.--
# # --So the current solution is to login to CSF manually and then run the script.--

# --- Step 2: Set Up Environment ---
echo "Setting up environment..."

# Load required modules (from CSF software list)
module load libs/cuda/12.0.1 #CUDA
module load apps/binapps/pytorch/2.3.0-311-gpu-cu121 #PyTorch
#module load apps/binapps/anaconda3/2024.10  # Python 3.12.7 and is supposed to be properly installed and setup from the beginning

# Navigate to your working directory (scratch-based)
WORKING_DIR="~/scratch/BEAD_analysis"
if [ ! -d "$WORKING_DIR" ]; then
    mkdir -p "$WORKING_DIR"
fi
cd "$WORKING_DIR"

# Clone the BEAD repository (if not already cloned)
if [ ! -d "BEAD" ]; then
    echo "Cloning BEAD repository..."
    git clone https://github.com/IBR-41379/BEAD.git
fi

# Navigate to the BEAD directory
cd BEAD/bead

# Install BEAD dependencies using Poetry (if not already installed)
if [ ! -d ".venv" ]; then
    echo "Setting up Poetry environment..."
    poetry install
fi

# --- Step 3: Define Workspace and Project ---
WORKSPACE="monotop_ws"
PROJECT="planar_vae_500epochs"

# Create new project structure (BEAD docs: Workspace/Project creation)
echo "Creating new workspace and project..."
poetry run bead -m new_project -p $WORKSPACE $PROJECT -v

# Move input data to the correct directory (assumes input CSV is available)
input_data="/path/to/your/input_data.csv" #If the user have personal csv files, else take it from BEAD/bead/workspaces/dq/data/csv
echo "Moving input data(CSV) to workspace..."
cp "$input_data" "workspaces/$WORKSPACE/data/csv/"

# --- Step 4: Modify Configuration File and write a shell script accordingly ---
CONFIG_FILE="workspaces/$WORKSPACE/$PROJECT/config/${PROJECT}_config.py"

# 1. Set model architecture (from BEAD example workflow)
echo "Updating model architecture to Planar_ConvVAE..."
sed -i "s/c\.model_name = .*/c.model_name = 'Planar_ConvVAE'/" $CONFIG_FILE

# 2. Training parameters (task requirements)
echo "Setting training parameters: 500 epochs, save every 100 epochs..."
sed -i "s/c\.epochs = .*/c.epochs = 500/" $CONFIG_FILE          # 500 total epochs
sed -i "s/c\.intermittent_saving_patience = .*/c.intermittent_saving_patience = 100/" "$CONFIG_FILE"
sed -i "s/c\.intermittent_model_saving = .*/c.intermittent_model_saving = True/" "$CONFIG_FILE"

# Create a job submission script
cat << 'EOF' > bead_job.sh
#!/bin/bash --login
# CSF Job Submission Script for BEAD Anomaly Detection (f@pou compliant)

# --- CSF Resource Requests (Serial Job) ---
#$ -cwd               # Run in current working directory
#$ -l nvidia_v100=1 	# Request 1 V100 GPU
										 # 7 day runtime default
                     # No memory flag = default 4GB/core (sufficient for BEAD)

# --- Module Loads (from CSF Software List) ---
module load libs/cuda/12.0.1 #CUDA
module load apps/binapps/pytorch/2.3.0-311-gpu-cu121 #PyTorch

# --- Full Pipeline Execution (BEAD chain mode docs) ---
# Convert CSV -> Prepare Inputs -> Train -> Detect
cd ~/scratch/BEAD_analysis/BEAD/bead
poetry run bead -m chain -p $WORKSPACE $PROJECT -o convertcsv_prepareinputs_train_detect -v

# --- Generate Final Plots (BEAD plotting docs) ---
# Produces both training and inference metrics
poetry run bead -m plot -p $WORKSPACE $PROJECT
EOF

# Make the script executable
chmod +x bead_job.sh

# Submit the job to CSF
qsub bead_job.sh

echo "Job submitted successfully!"

cp -r ~/scratch/BEAD_analysis/BEAD/bead/workspaces/monotop_ws ~/rds/monotop_project/Step4_$PROJECT



# --- Step 5: Run all other models ---
MODELS=("Planar_ConvVAE" "OrthogonalSylvester_ConvVAE" "HouseholderSylvester_ConvVAE" "TriangularSylvester_ConvVAE" "IAF_ConvVAE" "ConvFlow_ConvVAE" "NSFAR_ConvVAE")

# Loop through each model
for MODEL in "${MODELS[@]}"; do

    # Create a new project for the model
    NEW_PROJECT="${PROJECT}_${MODEL}"
    echo "Creating new project for $MODEL..."
    poetry run bead -m new_project -p $WORKSPACE $NEW_PROJECT -v

    # Update model architecture in config file
    echo "Updating model architecture to $MODEL..."
    NEW_CONFIG_FILE="workspaces/$WORKSPACE/$NEW_PROJECT/config/${NEW_PROJECT}_config.py"
    sed -i "s/c\.model_name = .*/c.model_name = '$MODEL'/" $NEW_CONFIG_FILE

    # Create a job submission script for the model
    cat << EOF > bead_job_${MODEL}.sh
#!/bin/bash --login
# CSF Job Submission Script for BEAD Anomaly Detection (f@pou compliant)
# --- CSF Resource Requests (Serial Job) ---
#$ -cwd               # Run in current working directory
#$ -l nvidia_v100=1 	# Request 1 V100 GPU
										 # 7 day runtime default
                     # No memory flag = default 4GB/core (sufficient for BEAD)

# --- Module Loads (from CSF Software List) ---
module load libs/cuda/12.0.1 #CUDA
module load apps/binapps/pytorch/2.3.0-311-gpu-cu121 #PyTorch

# --- Full Pipeline Execution (BEAD chain mode docs) ---
# Convert CSV -> Prepare Inputs -> Train -> Detect
cd ~/scratch/BEAD_analysis/BEAD/bead
poetry run bead -m chain -p $WORKSPACE $NEW_PROJECT -o convertcsv_prepareinputs_train_detect -v

# --- Generate Final Plots (BEAD plotting docs) ---
# Produces both training and inference metrics
poetry run bead -m plot -p $WORKSPACE $NEW_PROJECT
EOF

    # Make the script executable
    chmod +x bead_job_${MODEL}.sh

    # Submit the job to CSF
    qsub bead_job_${MODEL}.sh

    cp -r ~/scratch/BEAD_analysis/BEAD/bead/workspaces/$WORKSPACE/$NEW_PROJECT ~/rds/monotop_project/$NEW_PROJECT
    done
    echo "Job submitted successfully! Procedding to the next loop..."

echo "All Jobs submitted successfully! Exiting CSF..."
exit
