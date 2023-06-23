#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@author: C. Vriend with a little help from chatGPT :)
"""
import os
import shutil
import argparse
import matplotlib.pyplot as plt
from nilearn import plotting


def create_overlay(subjid,atlas,atlas_image, nodif_image, output_directory):
    # create a figure with multiple axes to plot each anatomical image
    fig, axes = plt.subplots(nrows=2, ncols=1, figsize=(20,10))

    display = plotting.plot_roi(atlas_image,
                                bg_img=nodif_image,
                                display_mode='y',
                                draw_cross=False,
                                alpha=0.8,
                                cmap='winter',
                                axes=axes[0])
    display = plotting.plot_roi(atlas_image,
                                bg_img=nodif_image,
                                display_mode='z',
                                draw_cross=False,
                                alpha=0.8,
                                cmap='winter',
                                axes=axes[1])
    output_file = os.path.join(output_directory,(subjid + "label-" + atlas + "_overlay.png"))
    fig.savefig(output_file)
    
    return output_file

def parse_arguments():
    parser = argparse.ArgumentParser(description='Create an overlay of an atlas on top of a nodif image.')
    parser.add_argument('--subjid', type=str, help='subject ID')
    parser.add_argument('--atlas', type=str, help='atlas name')
    parser.add_argument('--atlas_image', type=str, help='Path to the atlas image file')
    parser.add_argument('--nodif', type=str, help='Path to the nodif image file')
    parser.add_argument('--output', type=str, help='Output directory where the overlay PNG file will be saved')
    return parser.parse_args()

def main():
    # Parse command-line arguments
    args = parse_arguments()

    subjid=args.subjid
    atlas = args.atlas
    atlas_image = args.atlas_image
    nodif_image = args.nodif
    output_directory = args.output


    overlay_file = create_overlay(subjid,atlas,atlas_image, nodif_image, output_directory)
    print(f"Overlay file saved: {overlay_file}")

if __name__ == '__main__':
    main()