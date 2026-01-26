process boxplot_auc {
    publishDir "${params.outdir}/plots/", mode:"copy"
    input:
    path(summary_file)
    path(script_boxplot)
    output:
    path("boxplot.png"), emit: plot
    script:
    """
    Rscript $script_boxplot
    """
    stub:
    """
    touch boxplot.png
    """
}

process roc_auc_curve {
    publishDir "${params.outdir}/plots/", mode:"copy"
    input:
    tuple path(predictions_files), val(feature_extractor), val(mil)
    path(script_roc_auc)
    output:
    path("${feature_extractor}.${mil}.roc_auc.png"), emit: plot
    script:
    """
    Rscript $script_roc_auc $predictions_files ${feature_extractor}.${mil}.roc_auc.png
    """
    stub:
    """
    touch ${feature_extractor}.${mil}.roc_auc.png
    """
}
