﻿// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;
using Microsoft.DotNet.VersionTools.Automation;
using Microsoft.DotNet.VersionTools.Automation.GitHubApi;
using Microsoft.DotNet.VersionTools.BuildManifest;
using Microsoft.DotNet.VersionTools.BuildManifest.Model;
using System.IO;
using System.Linq;
using System.Xml.Linq;

namespace Microsoft.DotNet.Build.Tasks.Feed.BuildManifest
{
    public class PushOrchestratedBuildManifest : Task
    {
        [Required]
        public string ManifestFile { get; set; }

        [Required]
        public string VersionsRepoPath { get; set; }

        [Required]
        public string GitHubAuthToken { get; set; }
        public string GitHubUser { get; set; }
        public string GitHubEmail { get; set; }

        public string VersionsRepo { get; set; }
        public string VersionsRepoOwner { get; set; }

        public string VersionsRepoBranch { get; set; }

        public string CommitMessage { get; set; }

        /// <summary>
        /// %(Identity): A file to upload to the versions repo.
        /// %(RelativePath): Optional path to upload the file to, relative to VersionsRepoPath. 
        /// </summary>
        public ITaskItem[] SupplementaryFiles { get; set; }

        public override bool Execute()
        {
            string contents = System.IO.File.ReadAllText(ManifestFile);
            var model = OrchestratedBuildModel.Parse(XElement.Parse(contents));

            if (string.IsNullOrEmpty(CommitMessage))
            {
                CommitMessage = $"{model.Identity} orchestrated build manifest";
            }

            var gitHubAuth = new GitHubAuth(GitHubAuthToken, GitHubUser, GitHubEmail);
            using (var gitHubClient = new GitHubClient(gitHubAuth))
            {
                var client = new BuildManifestClient(gitHubClient);

                SupplementaryUploadRequest[] supplementaryUploads = SupplementaryFiles
                    ?.Select(i =>
                    {
                        string path = i.GetMetadata("RelativePath");
                        if (string.IsNullOrEmpty(path))
                        {
                            path = Path.GetFileName(i.ItemSpec);
                        }
                        return new SupplementaryUploadRequest
                        {
                            Contents = File.ReadAllText(i.ItemSpec),
                            Path = path
                        };
                    })
                    .ToArray();

                var pushTask = client.PushNewBuildAsync(
                    new GitHubProject(VersionsRepo, VersionsRepoOwner),
                    $"heads/{VersionsRepoBranch}",
                    VersionsRepoPath,
                    model,
                    supplementaryUploads,
                    CommitMessage);

                pushTask.Wait();
            }
            return !Log.HasLoggedErrors;
        }
    }
}
