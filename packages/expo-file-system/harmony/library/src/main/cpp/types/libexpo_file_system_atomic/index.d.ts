declare const atomicFileOperations: {
  exclusiveCreate(path: string): void;
  publishNoReplace(source: string, target: string): void;
};

export default atomicFileOperations;
