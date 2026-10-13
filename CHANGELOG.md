# Changelog

## [0.1.4](https://github.com/onahFran6/clusterdrill-lab/compare/clusterdrill-lab-v0.1.3...clusterdrill-lab-v0.1.4) (2026-10-13)


### Bug Fixes

* **bootstrap:** retry transient download failures in practice-tools.sh ([c765507](https://github.com/onahFran6/clusterdrill-lab/commit/c765507913935bd59d1638d297469dd17590abc1))
* **bootstrap:** retry transient download failures in practice-tools.sh ([#20](https://github.com/onahFran6/clusterdrill-lab/issues/20)) ([51a2c73](https://github.com/onahFran6/clusterdrill-lab/commit/51a2c738e2da2eb42ec2c0b876d75db68c520a0e))

## [0.1.3](https://github.com/onahFran6/clusterdrill-lab/compare/clusterdrill-lab-v0.1.2...clusterdrill-lab-v0.1.3) (2026-10-12)


### Features

* **bootstrap:** add opt-in practice GUI desktop for CKAD exam practice ([4ce2d41](https://github.com/onahFran6/clusterdrill-lab/commit/4ce2d4155a3135285fb0dea161b93be20bedc4ed))
* **bootstrap:** add opt-in practice GUI desktop for CKAD exam practice ([a498d57](https://github.com/onahFran6/clusterdrill-lab/commit/a498d5709761775af038bf62f298a6d959f96bca))
* **bootstrap:** bring Helm-based clusterdrill install, CKAD practice tooling, and practice GUI desktop to main ([1e2fa60](https://github.com/onahFran6/clusterdrill-lab/commit/1e2fa607b363865341824841bce48839ff0a1b2f))
* **bootstrap:** install clusterdrill via its published Helm chart, opt-in ([ffc4875](https://github.com/onahFran6/clusterdrill-lab/commit/ffc48758543eb509169f7124f6ca993332c08050))


### Bug Fixes

* **bootstrap:** make run.sh's /tmp/lib sync safe on a re-run ([c9a472c](https://github.com/onahFran6/clusterdrill-lab/commit/c9a472c0c002bade6d70c35e2afb43727e74c2cd))

## [0.1.2](https://github.com/onahFran6/clusterdrill-lab/compare/clusterdrill-lab-v0.1.1...clusterdrill-lab-v0.1.2) (2026-09-07)


### Features

* **bootstrap:** install helm and kustomize for CKAD practice ([#8](https://github.com/onahFran6/clusterdrill-lab/issues/8)) ([504ab5f](https://github.com/onahFran6/clusterdrill-lab/commit/504ab5f7c56a5d6132bd00c95960eff434ad2dfd))

## [0.1.1](https://github.com/onahFran6/clusterdrill-lab/compare/clusterdrill-lab-v0.1.0...clusterdrill-lab-v0.1.1) (2026-09-07)


### Bug Fixes

* **bootstrap:** make bootstrap resumable and catch bad config early ([a5e0650](https://github.com/onahFran6/clusterdrill-lab/commit/a5e0650379ba847a30afff2729ee5693742bf90c))

## 0.1.0 (2026-09-06)


### Bug Fixes

* appliance deploy hangs forever in any real (non-single-node) lab ([46eeb49](https://github.com/onahFran6/clusterdrill-lab/commit/46eeb49760cdd9ca1e188f55183c129ed6f32032))
* point release-please at main, not clusterdrill-lab ([3e2ec54](https://github.com/onahFran6/clusterdrill-lab/commit/3e2ec54c8fc6955e3eae595f3f61bd01126042b2))
* run.sh can't override which repo control-plane.sh installs from ([9e01e5f](https://github.com/onahFran6/clusterdrill-lab/commit/9e01e5f6365f597b4aa48b59126f1c9b61b39226))
* security group description rejects AWS's charset ([c9da55d](https://github.com/onahFran6/clusterdrill-lab/commit/c9da55dea7b36f5436f21d67fabae5e14d6ba18f))
* stop overriding the app-repo arg to the current repository ([0534cc6](https://github.com/onahFran6/clusterdrill-lab/commit/0534cc6064ea50e134c6d71feebe73a10eeb1fd1))
