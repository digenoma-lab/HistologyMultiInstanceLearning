include {
    grid_search_workflow;
} from './workflows/grid_search.nf'
include {
    plots;
} from './workflows/plots.nf'
include {
    heatmap_workflow;
} from './workflows/heatmap.nf'

workflow {
    dataset = Channel.value(file(params.dataset))

    feature_extractors = Channel.fromPath("${projectDir}/params/feature_extractors.csv")
        .splitCsv(header: true, sep: ',')
        .map { row ->
            tuple(
                row.patch_encoder,
                row.patch_size,
                row.mag,
                row.overlap
            )
        }

    architectures = Channel.fromPath("${projectDir}/params/architectures.csv")
        .splitCsv(header: true, sep: ',')
        .map { row ->
            tuple(row.architecture)
        }

    feature_paths = feature_extractors.map { row ->
        tuple(
            row[0],
            file("${params.features_dir}/${row[2]}x_${row[1]}px_${row[3]}px_overlap/features_${row[0]}/")
        )
    }

    transfer_settings = Channel.value(
        tuple(
            params.containsKey('transfer_mode') ? params.transfer_mode : 'scratch',
        params.containsKey('checkpoint_results_dir') ? params.checkpoint_results_dir : '',
        params.containsKey('checkpoint_fold') ? params.checkpoint_fold : 0,
        params.containsKey('folds') ? params.folds : 5,
        params.containsKey('best_params_dir') ? params.best_params_dir :
            (params.containsKey('grid_params_dir') ? params.grid_params_dir : '')
        )
    )

    configs = feature_paths
        .combine(architectures)
        .combine(transfer_settings)
        .map { feature_extractor, features_path, mil, transfer_mode, checkpoint_results_dir, checkpoint_fold, folds, grid_params_dir ->
            def grid_params = ''
            def checkpoint = ''

            if (grid_params_dir) {
                grid_params = "${grid_params_dir}/best_params_${feature_extractor}.${mil}.json"
            } else if (transfer_mode != 'scratch' && checkpoint_results_dir) {
                grid_params = "${checkpoint_results_dir}/best_params/best_params_${feature_extractor}.${mil}.json"
            }

            if (transfer_mode != 'scratch') {
                if (!checkpoint_results_dir) {
                    throw new IllegalArgumentException("checkpoint_results_dir is required for transfer_mode=${transfer_mode}")
                }
                checkpoint = "${checkpoint_results_dir}/models/${feature_extractor}.${mil}/${checkpoint_fold}_best_model.pt"
            }

            tuple(
                feature_extractor,
                features_path,
                mil,
                transfer_mode,
                grid_params,
                checkpoint,
                folds
            )
        }

    script_boxplot = Channel.value(file("${projectDir}/bin/boxplot_auc.R"))
    script_roc_auc = Channel.value(file("${projectDir}/bin/roc_auc_curve.R"))

    slides_dir = Channel.fromPath(params.slides_dir)

    grid_search_workflow(dataset, params.target, configs)

    plots(
        grid_search_workflow.out.summary,
        grid_search_workflow.out.predictions,
        script_boxplot,
        script_roc_auc
    )

    heatmap_workflow(
        grid_search_workflow.out.summary,
        grid_search_workflow.out.best_model_params,
        slides_dir,
        dataset
    )
}