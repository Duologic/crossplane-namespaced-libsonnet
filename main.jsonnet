local crossplane = import 'crossplane/main.libsonnet';

local xrd = crossplane.apiextensions.v1.compositeResourceDefinition;
local composition = crossplane.apiextensions.v1.composition;

local patch = crossplane.util.patch;
local xversion = crossplane.util.version;
local resource = crossplane.util.resource;

local addProperty = crossplane.util.version.addParameterProperty;

local createPatches(properties, parents=[]) =
  std.foldl(
    function(acc, k)
      local property = properties[k];
      acc +
      if property.type == 'object'
         && 'properties' in property
      then createPatches(property.properties, parents + [k])
      else [
        patch.fromCompositeFieldPath(
          std.join('.', ['spec', 'parameters'] + parents + [k]),
          std.join('.', ['spec'] + parents + [k])
        ),
      ],
    std.objectFields(properties),
    []
  );

function(crd=import 'crd.json', versionName='') {
  local this = self,

  local version = (
    if versionName != ''
    then std.filter(function(x) x.name == versionName, crd.spec.versions)[0]
    else std.filter(function(x) x.served, crd.spec.versions)[0]
  ).name,
  local spec = version.schema.openAPIV3Schema.properties.spec,

  version::
    xversion.new(version.name)
    + xversion.withPropertiesMixin({
      spec+: {
        properties+: {
          parameters+: spec,
        },
      },
    }),

  fakeInstance:: {
    new(n): {
      kind: crd.spec.names.kind,
      apiVersion: crd.spec.group + '/' + version.name,
    },
  },

  resource::
    resource.new(
      crd.spec.names.singular,
      self.fakeInstance,
    )
    + resource.withPatchesMixin(
      createPatches(spec.properties)
    ),

  local compositionName = crd.spec.names.singular + '-namespaced',

  definition:
    xrd.new(
      kind='X' + crd.spec.names.kind,
      plural='x' + crd.spec.names.plural,
      group=crd.spec.group + '.namespaced',
    )
    + xrd.withClaimNames(
      kind=crd.spec.names.kind,
      plural=crd.spec.names.plural,
    )
    + xrd.spec.defaultCompositionRef.withName(compositionName)
    + xrd.spec.withVersionsMixin([
      self.version,
    ]),

  composition:
    composition.new(compositionName)
    + composition.metadata.withAnnotations({
      // Tell Tanka to not set metadata.namespace.
      'tanka.dev/namespaced': 'false',
    })
    + composition.metadata.withLabels({
      'crossplane.io/xrd': this.definition.metadata.name,
    })
    + composition.spec.compositeTypeRef.withApiVersion(
      self.definition.spec.group + '/' + self.version.name
    )
    + composition.spec.compositeTypeRef.withKind(
      self.definition.spec.names.kind
    )
    + composition.spec.withResourcesMixin([
      self.resource,
    ]),
}
