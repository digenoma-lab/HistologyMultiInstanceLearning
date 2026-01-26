include {
    predict;
    select_best_config;
    convert_tiff;
    heatmap;
} from '../modules/heatmaps.nf'
workflow heatmap_workflow {
    take:
    summary
    best_model_params
    slides_dir
    dataset
    main:
    select_best_config(summary)
    best_model = best_model_params
        .combine(select_best_config.out.best_config)
        .filter{item -> 
            def match = item[4] == item[6] &&
                        item[5] == item[7]
            match
        }
        .map { item ->
                tuple(
                    item[0], item[1], item[2],
                    item[3], item[4], item[5]
                )
            }

    predict(best_model)
    row_dataset = dataset.splitCsv(header: true, sep: ',').map { row ->
        row.slide_id
    }
    heatmap_tuple = row_dataset.combine(slides_dir)
    heatmap_tuple = heatmap_tuple.combine(predict.out.attention_scores)
    heatmap(heatmap_tuple)
    convert_tiff(heatmap.out.heatmap)
    emit:
    heatmap = heatmap.out.heatmap
    convert_tiff = convert_tiff.out.heatmap_tiff
}
