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
    predict(best_model_params)
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
