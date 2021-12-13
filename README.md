<!-- omit in toc -->
# LVL Samrómur ASR

<img src="https://user-images.githubusercontent.com/9976294/84160937-4042f880-aa5e-11ea-8341-9f1963e0e84e.png" alt="Cover Image" align="center"/>

<p align="center"><i>
  NOTE! This is a project in development.
  
  Automatic Speech Recognition (ASR) system for the Samrómur speech corpus using <a href="http://kaldi-asr.org/">Kaldi</a><br/>
  Center for Analysis and Design of Intelligent Agents, Language and Voice Lab <br/>
  <a href="https://ru.is">Reykjavik University</a>
  
  This project is a research project on ASR creation. It does not contain trained ASR models or scripts on how to perform speech recognition using the models trained with the recipes provided here. [The Althingi recipe](https://github.com/cadia-lvl/kaldi/tree/master/egs/althingi) provides example scripts for how to run a Kaldi trained speech recognizer.
  
  We plan to have the recipes ready by October 2021 and create a Docker with the trained models.
</i></p>

<!-- omit in toc -->
## Table of Contents

<details>
<summary>Click to expand</summary>

- [1. Introduction](#1-introduction)
- [2. The Dataset](#2-the-dataset)
- [3. Setup](#3-setup)
- [4. Computing Requirements](#4-computing)
- [5. License](#5-license)
- [6. References](#6-references)
- [7. Contributing](#7-contributing)
- [8. Contributors](#8-contributors)

</details>

## 1. Introduction

Samrómur ASR is a collection of scripts, recipes, and tutorials for training an ASR using the [Kaldi-ASR](http://kaldi-asr.org/) toolkit.

[s5_base](/s5_base) is the regular ASR recipe. It's meant to be the foundation of our Samrómur recipes.
[s5_subwords](/s5_subwords) is a subword ASR recipe.
[s5_children](/s5_children) is a standard ASR recipe adapted towards children speech. 

[documentation](/documentation) contains information on data preparation for Kaldi and setup scripts
[preprocessing](/preprocessing) contains external tools for preprocessing and data preprocessing examples

## 2. The Dataset

The Samrómur speech corpus is an open (CC-BY 4 licence) and accessible database of voices that everyone is free to use when developing software in Icelandic.
The database consists of sentences and audio clips from the reading of those sentences as well as metadata about the speakers. Each entry in the database contains a WAVE audio clip and the corresponding text file.

The Samrómur speech corpus is available for download at [OpenSLR](https://www.openslr.org/112/).\
The Samrómur speech corpus will be available for download soon on [CLARIN-IS](http://clarin.is/gogn/) and [LDC](https://catalog.ldc.upenn.edu/).

For more information about the dataset visit [https://samromur.is/gagnasafn](https://samromur.is/gagnasafn).

## 3. Setup

You can use these guides for reference even if you do not use Terra (a cloud cluster at LVL).

- [Setup Guide for Kaldi-ASR](/documentation/setup_kaldi.md)
- [Setup Guide for Samrómur-ASR](/documentation/setup_samromur-asr.md)

## 4. Computing Requirements

This project is developed on a computing cluster with 112 CPUs and 10 GPUs (2 GeForce GTX Titan X, 4 GeForce GTX 1080 Ti, 4 GeForce RTX 2080 Ti). All of that is definitely not needed but the neural network acoustic model training scripts are intended to be used with GPUs. No GPUs are needed to use the trained models.

To do: Add training time info. My guess is around 24 hours for run.sh in s5_children on 135 hours of data.

## 5. License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 6. References
- [Samrómur](https://samromur.is/)
- [Language and Voice Lab](https://lvl.ru.is/)
- [Reykjavik University](https://www.ru.is/)
- [Kaldi-ASR](http://kaldi-asr.org/)

This project was funded by the Language Technology Programme for Icelandic 2019-2023. The programme, which is managed and coordinated by [Almannarómur](https://almannaromur.is/), is funded by the Icelandic Ministry of Education, Science and Culture.

## 7. Contributing

Pull requests are welcome. For significant changes, please open an issue first to discuss what you would like to change.
For more information, please take a look at [LVL Software Development Guidelines](https://github.com/cadia-lvl/SoftwareDevelopmentGuidelines).

## 8. Contributors

<a href="https://github.com/cadia-lvl/samromur-asr/graphs/contributors">
  <img src="https://contributors-img.web.app/image?repo=cadia-lvl/samromur-asr" />
</a>
<!-- Made with [contributors-img](https://contributors-img.web.app). -->

[Become a contributor](https://github.com/cadia-lvl/samromur-asr/pulls)

<p align="center">
🌟 PLEASE STAR THIS REPO IF YOU FOUND SOMETHING INTERESTING 🌟
</p>
