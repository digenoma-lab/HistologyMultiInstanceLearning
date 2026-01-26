process select_best_config {
    input:
    path(metrics)
    output:
    tuple env("feature_extractor"), env("mil"), emit: best_config
    script:
    """
    # Extraer la cabecera para identificar las columnas
    header=\$(head -n1 "${metrics}")
    # Obtener los índices de las columnas relevantes
    idx_feat=\$(echo "\$header" | tr ',' '\n' | awk '\$1=="feature_extractor"{print NR}')
    idx_mil=\$(echo "\$header" | tr ',' '\n' | awk '\$1=="mil"{print NR}')
    idx_auc=\$(echo "\$header" | tr ',' '\n' | awk '\$1=="test_auc"{print NR}')
    # Remover la cabecera y hacer el promedio agrupado
    awk -F, -v f=\$idx_feat -v m=\$idx_mil -v a=\$idx_auc '
    NR>1 { key=\$f FS \$m; sum[key]+\$a; count[key]++ }
    END {
        for (k in sum) {
            mean=sum[k]/count[k];
            print k, mean;
        }
    }' OFS=',' "${metrics}" > grouped_auc.csv

    # Buscar la configuración con mayor test_auc promedio
    best_line=\$(sort -t, -k3 -nr grouped_auc.csv | head -n1)
    feature_extractor=\$(echo "\$best_line" | cut -d, -f1)
    mil=\$(echo "\$best_line" | cut -d, -f2)
    """
    stub:
    """
    feature_extractor="virchow2"
    mil="clam"
    """
}

process predict { 
    publishDir "${params.outdir}/heatmaps/${feature_extractor}.${mil}", mode:"copy", pattern: "attention_scores"
    publishDir "${params.outdir}/heatmaps/${feature_extractor}.${mil}", mode:"copy", pattern: "predictions.csv"
    input:
    tuple path(dataset), path(features_path), path(best_params), path(best_model), val(feature_extractor), val(mil)
    output:
    tuple path(features_path), path("attention_scores"), val(feature_extractor), val(mil), emit: attention_scores
    path("predictions.csv"), emit: predictions
    script:
    """
    histomil-predict --csv_path $dataset \\
    --params_path $best_params --weights_path ${best_model[0]} \\
    --features_folder $features_path \\
    --feature_extractor $feature_extractor \\
    --mil $mil \\
    --results_dir ./
    """
    stub:
    """
    touch predictions.csv
    mkdir -p attention_scores/
    touch attention_scores/attention_scores.h5
    """
}

process heatmap {
    publishDir {
        "${params.outdir}/heatmaps/${feature_extractor}.${mil}/topk_patches/"
    }, mode:"copy", pattern: "$slide_id/topk_patches/*.png", saveAs: { filename -> "${slide_id}/${filename.split('/')[-1]}" }
    input:
    tuple val(slide_id), path(slide_folder), path(features_path), path(attention_scores), val(feature_extractor), val(mil)
    output:
    tuple val(feature_extractor), val(mil), val(slide_id), path("${slide_id}/heatmap_*.png"), path("$slide_id/topk_patches/top_*.png"), emit: heatmap
    script:
    """
    histomil-heatmap \\
    --slide_id $slide_id \\
    --slide_folder $slide_folder \\
    --features_folder $features_path \\
    --attn_scores_folder $attention_scores \\
    --results_dir ${slide_id}
    """
    stub:
    """
    mkdir -p  ${slide_id}/
    touch ${slide_id}/heatmap_${slide_id}.png
    mkdir -p ${slide_id}/topk_patches/
    touch ${slide_id}/topk_patches/top_0.png
    """
}
process convert_tiff {
    publishDir "${params.outdir}/heatmaps/${feature_extractor}.${mil}/tiff", mode:"copy", pattern: "*.tiff"
    input:
    tuple val(feature_extractor), val(mil), val(slide_id), path(heatmap_png), path(topk_patches_png)
    output:
    tuple val(feature_extractor), val(mil), path("${heatmap_png.simpleName}.tiff"), emit: heatmap_tiff
    script:
    """
    gdal_translate ${heatmap_png} ${heatmap_png.simpleName}.tiff \\
    -of GTiff \\
    -co TILED=YES \\
    -co BIGTIFF=YES \\
    -co COMPRESS=JPEG \\
    -co JPEG_QUALITY=90
    """
    stub:
    """
    touch ${heatmap_png.simpleName}.tiff
    """
}
