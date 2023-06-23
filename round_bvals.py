#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Tue Nov 30 10:25:01 2021

@author: c.vriend
"""
import pandas as pd
import argparse
import os

def roundbvals(base, number):
    nearest_multiple = round(base * round(number / base))
    return nearest_multiple

def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description='round bvals file.')
    parser.add_argument('bvals', help='Path to the bvals file')
    args = parser.parse_args()

    # Read bvals file
    bvals = pd.read_csv(args.bvals, sep=' ', header=None)

    # Round to nearest 1000 and store as integers
    bvals = bvals.apply(lambda row: roundbvals(1000, row), axis=0).astype(int)

    # Save rounded bvals to the output file
    bvals.to_csv(args.bvals, sep=' ', header=None, index=False)


if __name__ == '__main__':
    main()

