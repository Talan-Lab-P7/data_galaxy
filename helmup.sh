helm upgrade \
datagalaxy \
dg-charts/v1.17.8 \
-n datagalaxy \
--values "0-location.values.yaml" \
--values "0-size-resources.values.yaml" \
--values "0-size-storage.values.yaml" \
--values "1-release.values.yaml" \
--values "2-configuration.values.yaml" \
--values "3-authentication.values.yaml" \
--values "3-certificate.values.yaml"
