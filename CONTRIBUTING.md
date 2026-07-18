Contributing
============

Contributions are always welcome! Feel free to open a PR or an issue against
[BeamLabEU/beamlab_ex_aws_sqs](https://github.com/BeamLabEU/beamlab_ex_aws_sqs).

This project is a fork of [ex-aws/ex_aws_sqs](https://github.com/ex-aws/ex_aws_sqs). For
contributions to the broader `ex_aws` ecosystem, see
https://github.com/ex-aws/ex_aws/blob/master/CONTRIBUTING.md.

## Running the tests

Unit tests need no AWS access and no external services:

    mix test

The integration tests (`test/lib/sqs/integration_test.exs`, tagged `:external`) run against
[elasticmq](https://github.com/softwaremill/elasticmq), an SQS-compatible server expected on
`localhost:9324`:

    docker run -d --name elasticmq -p 9324:9324 softwaremill/elasticmq
    mix test --include external

That mirrors what CI does on every push (see `.github/workflows/on-push.yml`).
