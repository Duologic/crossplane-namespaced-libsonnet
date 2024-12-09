local namespaced = import './main.jsonnet';

namespaced.fromCRD(import 'crd.json')
