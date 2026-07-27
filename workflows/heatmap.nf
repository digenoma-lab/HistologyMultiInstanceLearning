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
    do_heatmap

    main:
    predict(best_model_params)

    // do_heatmap is a channel (not params.*) so cache keys stay consistent
    heatmap_inputs = do_heatmap
        .combine(
            dataset
                .splitCsv(header: true, sep: ',')
                .map { row -> row.slide_id }
        )
        .combine(slides_dir)
        .combine(predict.out.attention_scores)
        .filter { enabled, _slide_id, _slides, _features, _attn, _fe, _mil -> enabled }
        .map { _enabled, slide_id, slides, features, attn, fe, mil ->
            tuple(slide_id, slides, features, attn, fe, mil)
        }

    heatmap(heatmap_inputs)
    convert_tiff(heatmap.out.heatmap)

    emit:
    attention_scores = predict.out.attention_scores
    heatmap = heatmap.out.heatmap
    convert_tiff = convert_tiff.out.heatmap_tiff
}
