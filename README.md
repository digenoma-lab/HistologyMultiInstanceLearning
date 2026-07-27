## HistologyMultiInstanceLearning

<p align="center">
  <img src="imgs/logo.png" alt="Histology Multi Instance Learning Pipeline" width="40%"/>
</p>

**Multi-Instance Learning (MIL) pipeline** for histopathology to evaluate different **MIL architectures** (ABMIL, CLAM, DSMIL, etc.) using pre-extracted features from **foundation models** (for example, *uni_v2* and *virchow2*).

The workflow is implemented in **Nextflow DSL2** and uses containers (Wave/Singularity) to execute both the Python components for MIL training and grid search and the R components for result visualization.

The pipeline also supports **transfer learning from previously trained MIL checkpoints**, reusing the best hyperparameter configuration associated with each `feature_extractor × MIL architecture` combination.

---

### Pipeline overview

- **`main.nf`**  
  Orchestrates the pipeline:
  - Reads the clinical or dataset file from `params.dataset`.
  - Reads the list of feature extractors from `params/feature_extractors.csv`.
  - Reads the list of MIL architectures from `params/architectures.csv`.
  - Uses `params.features_dir` to construct the feature directory associated with each patch encoder.
  - Reads the selected training mode from `params.transfer_mode`.
  - Resolves the best-parameter file and pretrained checkpoint for each `feature_extractor × MIL architecture` combination when checkpoint-based training is enabled.
  - Launches:
    - `split_dataset`: splits the dataset into train, validation, and test folds at the case level.
    - `grid_search`: runs the grid search for each `feature_extractor × MIL architecture` combination using scratch or checkpoint-based training.
    - `concat_results`: concatenates all test metrics into a single summary file.
    - `boxplot_auc`: generates a global ROC AUC boxplot.
    - `roc_auc_curve`: generates ROC AUC curves for each configuration.
    - `heatmap_workflow`:
      - `select_best_config`: selects the best configuration based on validation AUC.
      - `predict`: generates predictions and attention scores for the selected model.
      - `heatmap`: creates heatmap visualizations for the highest-attention patches.
      - `convert_tiff`: converts generated heatmaps to TIFF format.

- **`modules/grid_search.nf`**
  - `process split_dataset`: runs `histomil-splits` to create train, validation, and test splits at the case level.
  - `process grid_search`: runs `histomil-grid` for each `feature_extractor × MIL architecture` combination.
  - Forwards the selected training mode and, when required, the resolved pretrained checkpoint and best-parameter configuration to HistoMILTrainer.
  - Publishes:
    - `test_results_*.csv`: test metrics for each fold.
    - `predictions_*.csv`: test predictions for each fold.
  - `process concat_results`: concatenates all test metrics into `summary.csv`.

- **`modules/plots.nf`**
  - `process boxplot_auc`: generates a boxplot comparing ROC AUC across all configurations using `bin/boxplot_auc.R`.
  - `process roc_auc_curve`: generates ROC AUC curves using `bin/roc_auc_curve.R`.

- **`modules/heatmaps.nf`**
  - `process select_best_config`: identifies the best hyperparameter configuration based on validation metrics.
  - `process predict`: runs `histomil-predict` to generate predictions and attention scores using the selected model.
  - `process heatmap`: runs `histomil-heatmap` to visualize attention scores on slide images.
  - `process convert_tiff`: converts generated heatmap images to tiled BigTIFF format using `gdal_translate`.

- **`bin/`**
  - `boxplot_auc.R`: reads `summary.csv` and generates a ROC AUC boxplot comparing feature extractors and MIL architectures.
  - `roc_auc_curve.R`: plots ROC curves from model predictions.

---

### Inputs

- **Dataset file** (`params.dataset`)
  - CSV file with at least:
    - `case_id`: case or patient identifier used for case-level splitting.
    - `slide_id`: slide identifier used to locate the corresponding feature file.
    - Target column: column specified by `params.target`, for example `target`, `ESR1`, or `MKI67`.

  - Example:
    ```csv
    case_id,slide_id,target
    case_1,slide_1,0
    case_1,slide_2,0
    case_2,slide_3,1
    case_2,slide_4,1
    ```

- **Feature extractors configuration** (`params/feature_extractors.csv`)
  - CSV file loaded by the pipeline from the `params/` directory.
  - Required columns:
    - `patch_encoder`: patch-level encoder name, for example `uni_v2` or `virchow2`.
    - `patch_size`: patch size in pixels.
    - `mag`: magnification level.
    - `overlap`: overlap in pixels.

  - Example:
    ```csv
    patch_encoder,patch_size,mag,overlap
    uni_v2,256,20,0
    virchow2,224,20,0
    ```

- **MIL architectures configuration** (`params/architectures.csv`)
  - CSV file loaded by the pipeline from the `params/` directory.
  - Required column:
    - `architecture`: MIL architecture name.

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
  - Base directory where the pre-extracted feature directories are located.
  - Feature directories follow the pattern:

    ```text
    {features_dir}{mag}x_{patch_size}px_{overlap}px_overlap/features_{patch_encoder}/
    ```

  - Each feature directory should contain one `{slide_id}.h5` file per slide.
  - Each H5 file should contain:
    - `features`: array with shape `(num_patches, feature_dim)`.
    - `coords`: optional array containing patch coordinates.

- **Slides directory** (`params.slides_dir`)
  - Base directory where the whole-slide images are located.
  - This input is used by the heatmap workflow to associate attention scores with the corresponding WSI.

---

### Pipeline parameters

The YAML file selected through `-params-file` defines the execution-specific configuration. The principal parameters are:

- `dataset`: path to the CSV file containing `case_id`, `slide_id`, and the target column.
- `features_dir`: base directory containing the pre-extracted feature directories.
- `slides_dir`: base directory containing the WSIs.
- `outdir`: output directory for the execution.
- `target`: name of the target column.
- `task`: learning task. Currently, `"classification"` is supported.
- `folds`: number of cross-validation folds.
- `transfer_mode`: training mode. Accepted values are `scratch`, `head_only`, and `partial`.
- `checkpoint_results_dir`: root directory containing the `best_params/` and `models/` directories from a previous source execution.
- `checkpoint_fold`: fold of the source execution used to select the pretrained checkpoint.

Example for scratch training:

```yaml
dataset: "/path/to/class_dataset.csv"
features_dir: "/path/to/features/base/directory/"
slides_dir: "/path/to/slides/base/directory/"
outdir: "./results_scratch/"
target: "target"
task: "classification"
folds: 5
transfer_mode: "scratch"
```

Example for checkpoint-based transfer:

```yaml
dataset: "/path/to/target_dataset.csv"
features_dir: "/path/to/target/features/"
slides_dir: "/path/to/target/slides/"
outdir: "./results_transfer/"
target: "target"
task: "classification"
folds: 5
transfer_mode: "head_only"
checkpoint_results_dir: "/path/to/source/results/"
checkpoint_fold: 0
```

---

### Parameter flow from YAML to HistoMILTrainer

The YAML file contains both pipeline-level inputs and training parameters. Nextflow reads these values through `params` and forwards the relevant entries to the corresponding HistoMILTrainer command.

The expected flow is:

```text
YAML file
   ↓
Nextflow params
   ↓
main.nf
   ↓
modules/grid_search.nf
   ↓
histomil-grid
   ↓
HistoMILTrainer
```

The parameters are used as follows:

- `dataset`, `features_dir`, `target`, `task`, and `folds` define the training dataset and cross-validation procedure.
- `transfer_mode` determines whether the model is trained from scratch or initialized from a previous checkpoint.
- `checkpoint_results_dir` is interpreted by the pipeline as the root of the source execution.
- For `head_only` and `partial`, the pipeline resolves the architecture-specific best-parameter file and checkpoint using the current feature extractor, MIL architecture, and `checkpoint_fold`.
- `slides_dir` is primarily required by prediction and heatmap generation rather than by the core grid-search training step.
- `outdir` controls where Nextflow publishes the outputs of the current execution.

The exact HistoMILTrainer command-line options are assembled by the Nextflow modules. Therefore, YAML parameter names should remain synchronized with the parameters referenced in `main.nf` and `modules/grid_search.nf`.

---

### Transfer learning

The pipeline supports three training modes:

- **`scratch`**: trains the selected MIL architecture from random initialization.
- **`head_only`**: loads compatible weights from a pretrained checkpoint and trains only the classification head or architecture-specific output heads.
- **`partial`**: loads a pretrained checkpoint and trains the architecture-specific subset of MIL layers configured in HistoMILTrainer.

The `partial` mode uses the trainable-module configuration defined for each MIL architecture in HistoMILTrainer.

For checkpoint-based modes, `checkpoint_results_dir` should contain the best parameters and model checkpoints generated by a previous pipeline execution:

```text
checkpoint_results_dir/
├── best_params/
│   └── best_params_{feature_extractor}.{mil}.json
└── models/
    └── {feature_extractor}.{mil}/
        └── {checkpoint_fold}_best_model.pt
```

The feature extractor and MIL architecture names used in the target execution must match the names used in the source execution. Otherwise, the pipeline will not be able to resolve the corresponding best-parameter file or pretrained model.

---

### Outputs

All outputs are written under `params.outdir`.

- **Training results**
  - `training/`
    - `summary.csv`: concatenated test metrics.
    - `{feature_extractor}.{mil}/`
      - `test_results_{feature_extractor}.{mil}.csv`: metrics for each fold.
    - Classification metrics include `test_auc`, `test_acc`, `test_f1`, `test_precision`, and `test_recall`.

- **Predictions**
  - `predictions/`
    - `{feature_extractor}.{mil}/`
      - `predictions_{feature_extractor}.{mil}_{fold}.csv`: predictions containing `slide_id`, `y_true`, `y_pred`, and `y_score`.

- **Splits**
  - `splits/`
    - `{target}/`
      - `dataset.csv`.
      - `splits_{fold}_bool.csv`.
      - `splits_{fold}_descriptor.csv`.

- **Plots**
  - `plots/`
    - `boxplot.png`.
    - `*.roc_auc.png`.

- **Heatmaps**
  - `heatmaps/{feature_extractor}.{mil}/`
    - `attention_scores/`.
    - `predictions.csv`.
    - `topk_patches/`.
    - `tiff/`.

- **Pipeline information**
  - `pipeline_info/`: Nextflow timeline, report, trace, and DAG files.

---

### Requirements

- **Nextflow** ≥ 22.x.
- Access to Singularity or Wave containers as configured in `nextflow.config`.
- A cluster with **SLURM** when using the `kutral` profile.
- [HistoMILTrainer transfer-learning branch](https://github.com/alanEmolina/HistoMILTrainer/tree/feature/mil-transfer-learning) for `head_only` and `partial` training.

---

### Basic usage

1. Load the environment where Nextflow and Singularity are available.

2. Build the Singularity container for [HistoMILTrainer](https://github.com/alanEmolina/HistoMILTrainer/tree/feature/mil-transfer-learning):

   ```bash
   cd singularity/
   singularity build histomil.sif histomil.def
   ```

3. Configure the feature extractors in `params/feature_extractors.csv`.

4. Configure the MIL architectures in `params/architectures.csv`.

5. Choose or edit a YAML file in `params/`:
   - Set `dataset`.
   - Set `features_dir`.
   - Set `slides_dir`.
   - Set `outdir`.
   - Set `target`.
   - Set `task`.
   - Set `folds`.
   - Set `transfer_mode`.
   - For `head_only` or `partial`, set `checkpoint_results_dir` and `checkpoint_fold`.

6. Run the pipeline:

```bash
# Scratch training
nextflow run main.nf -profile kutral \
  -params-file params/params_scratch.yml

# Head-only transfer
nextflow run main.nf -profile kutral \
  -params-file params/params_transfer_head_only.yml

# Partial transfer
nextflow run main.nf -profile kutral \
  -params-file params/params_transfer_partial.yml
```

For local execution without SLURM:

```bash
nextflow run main.nf -profile local \
  -params-file params/params_scratch.yml
```

To resume an interrupted execution:

```bash
nextflow run main.nf -profile kutral \
  -params-file params/params_transfer_head_only.yml \
  -resume
```

---

### Supported MIL architectures

The pipeline supports multiple MIL architectures from [MIL-Lab](https://github.com/mahmoodlab/MIL-Lab):

- **ABMIL**: Attention-based Multiple Instance Learning.
- **CLAM**: Clustering-constrained Attention Multiple Instance Learning.
- **DSMIL**: Dual-stream Multiple Instance Learning.
- **DFTD**: Deep Feature-based Top-Down Attention.
- **ILRA**: Instance-Level Representation Aggregation.
- **RRT**: Residual Regression Transformer.
- **Transformer**: Transformer-based MIL.
- **TransMIL**: Transductive Multiple Instance Learning.
- **WIKG**: Weighted Instance Knowledge Graph.

Each architecture is configured through HistoMILTrainer JSON files in `histomil/configs/req_grid/`. These files also define the architecture-specific trainable modules used by `partial` transfer learning.

> **Note**: CLAM automatically sets `batch_size` to 1 during training. MIL-Lab must be installed and accessible in the HistoMILTrainer environment.

---

### Output directory structure

```text
results/
├── splits/
│   └── {target}/
│       ├── dataset.csv
│       ├── splits_0_bool.csv
│       ├── splits_0_descriptor.csv
│       └── ...
├── training/
│   ├── summary.csv
│   ├── {feature_extractor}.{mil}/
│   │   └── test_results_{feature_extractor}.{mil}.csv
│   └── ...
├── predictions/
│   ├── {feature_extractor}.{mil}/
│   │   ├── predictions_{feature_extractor}.{mil}_0.csv
│   │   ├── predictions_{feature_extractor}.{mil}_1.csv
│   │   └── ...
│   └── ...
├── plots/
│   ├── boxplot.png
│   └── *.roc_auc.png
├── heatmaps/
│   ├── {feature_extractor}.{mil}/
│   │   ├── attention_scores/
│   │   ├── predictions.csv
│   │   ├── topk_patches/
│   │   └── tiff/
│   └── ...
└── pipeline_info/
    ├── execution_report_*.html
    ├── execution_timeline_*.html
    ├── execution_trace_*.txt
    └── pipeline_dag_*.html
```

---

### Tips and best practices

1. Ensure that the `patch_encoder`, `patch_size`, `mag`, and `overlap` values in `params/feature_extractors.csv` match the physical directory structure under `features_dir`.

2. The dataset is split at the case level to prevent data leakage. Multiple slides from the same case remain in the same train, validation, or test partition.

3. Configure the number of cross-validation folds through `folds` in the selected YAML file.

4. Grid-search processes can be memory- and GPU-intensive. Adjust resource allocations in `nextflow.config` when required.

5. Use `-resume` to continue interrupted Nextflow executions.

6. Store pre-extracted features in H5 format, with one `{slide_id}.h5` file per slide.

7. Keep the source execution's `best_params/` and `models/` directories under the same `checkpoint_results_dir`.

8. Preserve consistent feature extractor and MIL architecture names between source and target executions.

9. Keep execution-specific paths in YAML parameter files rather than hard-coding them in Nextflow modules, container definitions, environment files, or Trainer source code.

---

### Citation

If you use this pipeline in your research, please cite:

- **MIL-Lab**: repository containing the MIL architectures used in this pipeline.
  - Repository: [https://github.com/mahmoodlab/MIL-Lab](https://github.com/mahmoodlab/MIL-Lab)

- **HistoMIL**: library used for training MIL architectures on histology data.
  - Repository: [https://github.com/digenoma-lab/HistoMIL](https://github.com/digenoma-lab/HistoMIL)

- **This pipeline**: cite this repository when using the complete Nextflow workflow.

---

### Contact

Author: **Gabriel Cabas**  
For questions or suggestions, open an *issue* or *pull request* in this repository.