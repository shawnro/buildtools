﻿// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using System;
using System.Collections.Generic;
using System.Diagnostics.Contracts;
using System.Linq;
using Microsoft.Cci.Extensions;
using Microsoft.Cci.Extensions.CSharp;

namespace Microsoft.Cci.Differs.Rules
{
    // Look for differences in a parameter's marshaling attributes like in, out, & ref, as well as 
    // potentially custom modifiers like const & volatile.
    [ExportDifferenceRule]
    internal class ParameterModifiersCannotChange : DifferenceRule
    {
        public override DifferenceType Diff(IDifferences differences, ITypeDefinitionMember impl, ITypeDefinitionMember contract)
        {
            if (impl == null || contract == null)
                return DifferenceType.Unknown;

            IMethodDefinition method1 = impl as IMethodDefinition;
            IMethodDefinition method2 = contract as IMethodDefinition;

            if (method1 == null || method2 == null)
                return DifferenceType.Unknown;

            if (!CheckModifiersOnParametersAndReturnValue(differences, method1, method2))
                return DifferenceType.Changed;

            return DifferenceType.Unknown;
        }

        private bool CheckModifiersOnParametersAndReturnValue(IDifferences differences, IMethodDefinition implMethod, IMethodDefinition contractMethod)
        {
            int paramCount = implMethod.ParameterCount;

            Contract.Assert(paramCount == contractMethod.ParameterCount);

            if (paramCount == 0)
                return true;

            IParameterDefinition[] implParams = implMethod.Parameters.ToArray();
            IParameterDefinition[] contractParams = contractMethod.Parameters.ToArray();

            bool match = true;
            for (int i = 0; i < paramCount; i++)
            {
                IParameterDefinition implParam = implParams[i];
                IParameterDefinition contractParam = contractParams[i];

                //TODO: Do we care about the compatibility with marshalling attributes Out\In? They don't seem to be set consistently.

                if (GetModifier(implParam) != GetModifier(contractParam))
                {
                    differences.AddIncompatibleDifference(this,
                        "Modifiers on parameter '{0}' on method '{1}' are '{2}' in the implementation but '{3}' in the contract.",
                        implParam.Name.Value, implMethod.FullName(), GetModifier(implParam), GetModifier(contractParam));
                    match = false;
                }

                // Now check custom modifiers, primarily focused on const & volatile
                if (implParam.IsModified || contractParam.IsModified)
                {
                    var union = implParam.CustomModifiers.Union(contractParam.CustomModifiers);
                    if (implParam.CustomModifiers.Count() != union.Count())
                    {
                        differences.AddIncompatibleDifference(this,
                            "Custom modifiers on parameter '{0}' on method '{1}' are '{2}' in the implementation but '{3}' in the contract.",
                            implParam.Name.Value, implMethod.FullName(), PrintCustomModifiers(implParam.CustomModifiers), PrintCustomModifiers(contractParam.CustomModifiers));
                        match = false;
                    }
                }
            }

            string implReturnModifier = GetReturnValueModifier(implMethod);
            string contractReturnModifier = GetReturnValueModifier(contractMethod);

            if (implReturnModifier != contractReturnModifier)
            {
                differences.AddIncompatibleDifference(this,
                    "Modifiers on return type of method '{0}' are '{1}' in the implementation but '{2}' in the contract.",
                    implMethod.FullName(), implReturnModifier, contractReturnModifier);
                match = false;
            }

            return match;
        }

        private string GetModifier(IParameterDefinition parameter)
        {
            if (parameter.IsOut && !parameter.IsIn && parameter.IsByReference)
            {
                return "out";
            }
            else if (parameter.IsByReference)
            {
                if (parameter.Attributes.HasIsReadOnlyAttribute())
                {
                    return "in";
                }

                return "ref";
            }

            return "<none>";
        }

        private String PrintCustomModifiers(IEnumerable<ICustomModifier> modifiers)
        {
            String s = String.Join(", ", modifiers.Select(m => m.Modifier.FullName()));
            if (String.IsNullOrEmpty(s))
                return "<no custom modifiers>";
            return s;
        }

        private string GetReturnValueModifier(IMethodDefinition method)
        {
            string modifier = "<none>";
            if (method.ReturnValueIsByRef)
            {
                modifier = "ref";

                if (method.ReturnValueAttributes.HasIsReadOnlyAttribute())
                    modifier += " readonly";
            }
            return modifier;
        }
    }
}
