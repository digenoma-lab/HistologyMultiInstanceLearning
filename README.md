## HistologyMultiInstanceLearning

**Multi-Instance Learning (MIL) pipeline** for histopathology to evaluate different **MIL architectures** (ABMIL, CLAM, DSMIL, etc.) using pre-extracted features from **foundation models** (for example, *uni_v2*, *virchow2*).

The workflow is implemented in **Nextflow DSL2** and uses containers (Wave/Singularity) to run both the Python part (MIL training and grid search) and the R part (visualizations).

---

### Pipeline overview

- **`main.nf`**  
  Orchestrates the pipeline:
  - Reads the clinical/dataset file (`params.dataset`).
  - Reads the list of feature extractors from `params/feature_extractors.csv` (automatically loaded).
  - Reads the list of MIL architectures from `params/architectures.csv` (automatically loaded).
  - Uses `params.features_dir` to construct feature directory paths.
  - Launches:
    - `split_dataset`: splits the dataset into train/val/test folds for cross-validation at the case level.
    - `grid_search`: runs grid-search for each `feature_extractor × MIL architecture` combination with cross-validation.
    - `concat_results`: concatenates all test metrics into a single summary file.
    - `boxplot_auc`: generates a global performance boxplot (ROC AUC).

- **`modules/grid_search.nf`**
  - `process split_dataset`: runs `bin/HistoMILTrainer/make_splits.py` to create train/val/test splits for cross-validation at the case level.
  - `process grid_search`: runs `bin/HistoMILTrainer/grid_search.py` for each `feature_extractor × MIL architecture` combination and publishes:
    - `test_results_*.csv` (test set metrics per fold)
    - `predictions_*.csv` (test set predictions per fold)
  - `process concat_results`: concatenates all test metrics into a single `summary.csv` file.
  - `process boxplot_auc`: generates a boxplot comparing ROC AUC across all configurations using `bin/boxplot_auc.R`.

- **`bin/`**
  - `HistoMILTrainer/make_splits.py`: creates train/val/test splits for cross-validation at the case level (prevents data leakage).
  - `HistoMILTrainer/grid_search.py`: trains MIL models with cross-validation, performs hyperparameter grid search, and saves results and predictions.
  - `boxplot_auc.R`: reads the `summary.csv` file and generates a ROC AUC `boxplot.png` comparing performance across feature extractors and MIL architectures.

---

### Inputs

- **Dataset file** (`params.dataset`)
  - CSV with at least:
    - A `case_id` column to identify cases (patients) for case-level splitting.
    - A `slide_id` column to link samples with feature files.
    - A target column (specified by `params.target`, e.g., `target`, `ESR1`, `MKI67`).
  - Example structure:
    ```csv
    case_id,slide_id,target
    case_1,slide_1,0
    case_1,slide_2,0
    case_2,slide_3,1
    case_2,slide_4,1
    ...
    ```

- **Feature extractors configuration** (`params/feature_extractors.csv`)
  - CSV file automatically loaded by the pipeline (located in `params/` directory).
  - Required columns:
    - `patch_encoder`: patch-level encoder name (e.g. `uni_v2`, `virchow2`).
    - `patch_size`: patch size in pixels (e.g. `256`, `224`).
    - `mag`: magnification level (e.g. `20`).
    - `overlap`: overlap in pixels (e.g. `0`).
  - Example:
    ```csv
    patch_encoder,patch_size,mag,overlap
    uni_v2,256,20,0
    virchow2,224,20,0
    ```

- **MIL architectures configuration** (`params/architectures.csv`)
  - CSV file automatically loaded by the pipeline (located in `params/` directory).
  - Required columns:
    - `architecture`: MIL architecture name (e.g. `abmil`, `clam`, `dsmil`, `dftd`, `ilra`, `rrt`, `transformer`, `transmil`, `wikg`).
  - Example:
    ```csv
    architecture
    abmil
    clam
    dsmil
    dftd
    ilra
    rrt
    transformer
    transmil
    wikg
    ```

- **Features directory** (`params.features_dir`)
  - Base directory path where feature directories are located.
  - Feature directories follow the pattern: `{features_dir}{mag}x_{patch_size}px_{overlap}px_overlap/features_{patch_encoder}/`
  - Each feature directory should contain one `.h5` file per slide (named `{slide_id}.h5`).
  - Each H5 file should contain:
    - `features`: Array of shape `(num_patches, feature_dim)`
    - Optionally: `coords`: Array of patch coordinates

- **Pipeline parameters** (YAML files in `params/`)
  - The key parameters are:
    - `dataset`: path to the CSV with case_id, slide_id, and target columns.
    - `features_dir`: base directory path where feature directories are located.
    - `outdir`: output directory for this run (default: `./results/`).
    - `target`: column name of the target variable (e.g., `target`, `ESR1`, `MKI67`).
    - `task`: `"classification"` (currently only classification is supported).

  - Example:
    - **HRR ER classification** (`params/params_hrr_er.yml`):
      ```yaml
      dataset: '/path/to/class_dataset_er.csv'
      features_dir: "/path/to/features/base/directory/"
      outdir: "./results_hrr_er/"
      target: "target"
      task: "classification"
      ```

---

### Outputs

All outputs are written under `params.outdir` (configured in the selected params file):

- **Training results**
  - `training/`
    - `summary.csv` (concatenated test metrics from all feature extractors and MIL architectures).
    - `{feature_extractor}.{mil}/`
      - `test_results_{feature_extractor}.{mil}.csv` with metrics per fold.
    - Classification metrics: `test_auc`, `test_acc`, `test_f1`, `test_precision`, `test_recall`.

- **Predictions**
  - `predictions/`
    - `{feature_extractor}.{mil}/`
      - `predictions_{feature_extractor}.{mil}_{fold}.csv` with `slide_id`, `y_true`, `y_pred`, `y_score` (probability for the positive class).

- **Splits**
  - `splits/`
    - `{target}/`
      - `dataset.csv` (processed dataset with case_id, slide_id, and label columns).
      - `splits_{fold}_bool.csv` (boolean splits for each fold with train/val/test columns).
      - `splits_{fold}_descriptor.csv` (summary statistics for each split).

- **Plots**
  - `plots/boxplot.png`:  
    Distribution of ROC AUC by `feature_extractor` and `mil` architecture.

- **Pipeline information**
  - `pipeline_info/` (timeline, report, trace, DAG HTML) generated automatically by Nextflow.

---

### Requirements

- **Nextflow** ≥ 22.x
- Access to Singularity/Wave containers (configured in `nextflow.config`).
- Cluster with **SLURM** if using the `kutral` profile (default in this repo).
- Python dependencies (provided via containers or local installation):
  - `torch`, `numpy`, `pandas`, `h5py`, `scikit-learn`, `tqdm`
  - Access to **MIL-Lab** repository (see [HistoMILTrainer README](bin/HistoMILTrainer/README.md))
- R dependencies (provided via containers):
  - `ggplot2`, `readr`, `dplyr`, `stringr`

> **Note**: You do **not** need to manually install the R dependencies: they are provided through the containers declared in `nextflow.config`. The pipeline uses Wave containers from the Seqera community registry. However, Python dependencies (including MIL-Lab) need to be installed in your environment or provided via a container.

---

### Basic usage

1. **Load the environment** where Nextflow and Singularity are available.
2. **Install HistoMILTrainer dependencies**: Follow the instructions in [bin/HistoMILTrainer/README.md](bin/HistoMILTrainer/README.md) to install MIL-Lab and HistoMIL.
3. **Configure feature extractors**: Ensure `params/feature_extractors.csv` exists and contains the feature extractor configurations you want to evaluate.
4. **Configure MIL architectures**: Ensure `params/architectures.csv` exists and contains the MIL architectures you want to evaluate.
5. **Choose or edit a params file** in `params/` directory:
   - Set `dataset`: path to your CSV with case_id, slide_id, and target columns.
   - Set `features_dir`: base directory where feature directories are located.
   - Set `target`: column name of the target variable (e.g., `target`, `ESR1`, `MKI67`).
   - Set `outdir`: output directory for this run.
   - Set `task`: `"classification"` (currently only classification is supported).
6. **Run the pipeline**:

```bash
# HRR ER classification
nextflow run main.nf -profile kutral -params-file params/params_hrr_er.yml

# MKI67 classification
nextflow run main.nf -profile kutral -params-file params/params_mki67_class.yml
```

For **local execution** (without SLURM), you can use the `local` profile defined in `nextflow.config`:

```bash
nextflow run main.nf -profile local -params-file params/params_hrr_er.yml
```

### Supported MIL architectures

The pipeline supports multiple state-of-the-art MIL architectures from [MIL-Lab](https://github.com/mahmoodlab/MIL-Lab):

- **ABMIL**: Attention-based Multiple Instance Learning
- **CLAM**: Clustering-constrained Attention Multiple instance learning
- **DSMIL**: Dual-stream Multiple Instance Learning
- **DFTD**: Deep Feature-based Top-Down attention
- **ILRA**: Instance-Level Representation Aggregation
- **RRT**: Residual Regression Transformer
- **Transformer**: Transformer-based MIL
- **TransMIL**: Transductive Multiple Instance Learning
- **WIKG**: Weighted Instance Knowledge Graph

Each architecture can be configured via JSON files in `bin/HistoMILTrainer/configs/`. The pipeline uses 3-fold cross-validation by default (configurable in `grid_search.py`).

> **Note**: CLAM automatically sets batch_size to 1 during training. Make sure MIL-Lab is properly installed and accessible in your Python path.

---

### Output directory structure

After running the pipeline, the output directory (`params.outdir`) will have the following structure:

```
results/
├── splits/                    # Train/val/test splits
│   ├── target/
│   │   ├── dataset.csv
│   │   ├── splits_0_bool.csv
│   │   ├── splits_0_descriptor.csv
│   │   └── ...
│   └── ...
├── training/                  # Training results
│   ├── summary.csv            # Concatenated summary
│   ├── {feature_extractor}.{mil}/
│   │   └── test_results_{feature_extractor}.{mil}.csv
│   └── ...
├── predictions/               # Test set predictions
│   ├── {feature_extractor}.{mil}/
│   │   ├── predictions_{feature_extractor}.{mil}_0.csv
│   │   ├── predictions_{feature_extractor}.{mil}_1.csv
│   │   └── ...
│   └── ...
├── plots/                     # Generated plots
│   └── boxplot.png            # ROC AUC comparison boxplot
└── pipeline_info/              # Nextflow execution reports
    ├── execution_report_*.html
    ├── execution_timeline_*.html
    ├── execution_trace_*.txt
    └── pipeline_dag_*.html
```

---

### Tips and best practices

1. **Feature extractor configuration**: Make sure the `patch_encoder`, `patch_size`, `mag`, and `overlap` values in `params/feature_extractors.csv` match the directory structure in your `features_dir`.

2. **Case-level splitting**: The pipeline splits data at the case level to prevent data leakage. Multiple slides from the same case will always be in the same split (train/val/test).

3. **Cross-validation**: The pipeline uses 3-fold cross-validation by default. Each fold generates separate test metrics and predictions.

4. **Memory and GPU requirements**: Grid search processes can be memory and GPU-intensive. The default configuration allocates 80G memory, 16 CPUs, and 1 GPU for grid search processes. Adjust in `nextflow.config` if needed.

5. **Resume execution**: Nextflow supports resuming failed runs. Use `-resume` flag:
   ```bash
   nextflow run main.nf -profile kutral -params-file params/params_hrr_er.yml -resume
   ```

6. **Feature format**: Features should be pre-extracted and stored in H5 format. Each slide should have a corresponding `{slide_id}.h5` file containing the `features` array.

7. **MIL-Lab installation**: Make sure MIL-Lab is properly installed and accessible. See [HistoMILTrainer README](bin/HistoMILTrainer/README.md) for installation instructions.

---

### Citation

If you use this pipeline in your research, please cite:

- **MIL-Lab**: The repository containing the MIL architectures used in this pipeline
  - Repository: [https://github.com/mahmoodlab/MIL-Lab](https://github.com/mahmoodlab/MIL-Lab)
  - Please cite the original MIL-Lab paper and the specific architecture papers you use

- **HistoMIL**: The library used for training MIL architectures on histology data
  - Repository: [https://github.com/digenoma-lab/HistoMIL](https://github.com/digenoma-lab/HistoMIL)
  - Please cite the HistoMIL library if you use it in your research

- **This pipeline**: If you use this Nextflow pipeline, please cite this repository

---

### Contact

Author: **Gabriel Cabas**  
For questions or suggestions, please open an *issue* or *pull request* in this repository.
